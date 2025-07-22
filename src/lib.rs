use pgrx::prelude::*;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use std::sync::{Mutex, LazyLock};
use std::collections::HashMap;

::pgrx::pg_module_magic!();

// Constants matching the Dart implementation
const MAX_COUNTER: i32 = 0xFFFF;
const MAX_DRIFT_MINUTES: i64 = 1;

// Global HLC instances per node with thread safety
static GLOBAL_HLCS: LazyLock<Mutex<HashMap<String, HlcState>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

// Internal state for each HLC node
#[derive(Debug, Clone)]
struct HlcState {
    date_time: DateTime<Utc>,
    counter: i32,
    node_id: String,
}

impl HlcState {
    fn new(node_id: String) -> Self {
        HlcState {
            date_time: DateTime::from_timestamp(0, 0).unwrap_or_else(|| Utc::now()),
            counter: 0,
            node_id,
        }
    }
}

// Custom PostgreSQL type for HLC timestamps - matching Dart HLC structure
#[derive(PostgresType, Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct HlcTimestamp {
    pub date_time: String, // ISO8601 string representation
    pub counter: i32,
    pub node_id: String,
}

// Implement InOutFuncs manually for HlcTimestamp
impl InOutFuncs for HlcTimestamp {
    fn input(input: &std::ffi::CStr) -> HlcTimestamp
    where
        Self: Sized,
    {
        let input_str = input.to_str().unwrap_or("");
        HlcTimestamp::parse(input_str).unwrap_or_else(|_| HlcTimestamp {
            date_time: "1970-01-01T00:00:00Z".to_string(),
            counter: 0,
            node_id: "unknown".to_string(),
        })
    }

    fn output(&self, buffer: &mut pgrx::StringInfo) {
        buffer.push_str(&self.to_string());
    }
}

// Implement ordering for HLC timestamps - matching Dart compareTo logic
impl PartialOrd for HlcTimestamp {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for HlcTimestamp {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        let self_dt = DateTime::parse_from_rfc3339(&self.date_time)
            .unwrap_or_else(|_| DateTime::from_timestamp(0, 0).unwrap().into());
        let other_dt = DateTime::parse_from_rfc3339(&other.date_time)
            .unwrap_or_else(|_| DateTime::from_timestamp(0, 0).unwrap().into());

        // Match Dart compareTo: compare dateTime first, then counter, then nodeId
        match self_dt.cmp(&other_dt) {
            std::cmp::Ordering::Equal => {
                match self.counter.cmp(&other.counter) {
                    std::cmp::Ordering::Equal => self.node_id.cmp(&other.node_id),
                    other => other,
                }
            }
            other => other,
        }
    }
}

impl HlcTimestamp {
    // Parse HLC from string format matching Dart: "ISO8601-counter-nodeId"
    fn parse(timestamp: &str) -> Result<Self, String> {
        let parts: Vec<&str> = timestamp.rsplitn(3, '-').collect();
        if parts.len() != 3 {
            return Err("Invalid HLC format".to_string());
        }

        let node_id = parts[0].to_string();
        let counter = i32::from_str_radix(parts[1], 16)
            .map_err(|_| "Invalid counter format")?;
        let date_time = parts[2].to_string();

        // Validate the datetime
        DateTime::parse_from_rfc3339(&date_time)
            .map_err(|_| "Invalid datetime format")?;

        Ok(HlcTimestamp {
            date_time,
            counter,
            node_id,
        })
    }

    // Format to string matching Dart toString: "ISO8601-counter-nodeId"
    fn to_string(&self) -> String {
        format!("{}-{:04X}-{}", self.date_time, self.counter, self.node_id)
    }

    // Create from internal state
    fn from_state(state: &HlcState) -> Self {
        HlcTimestamp {
            date_time: state.date_time.to_rfc3339(),
            counter: state.counter,
            node_id: state.node_id.clone(),
        }
    }
}

// Error types matching Dart exceptions
#[derive(Debug)]
enum HlcError {
    ClockDrift { drift_minutes: i64 },
    Overflow { counter: i32 },
    DuplicateNode { node_id: String },
}

impl std::fmt::Display for HlcError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            HlcError::ClockDrift { drift_minutes } => {
                write!(f, "Clock drift of {} minutes exceeds maximum ({})", drift_minutes, MAX_DRIFT_MINUTES)
            }
            HlcError::Overflow { counter } => {
                write!(f, "Timestamp counter overflow: {}", counter)
            }
            HlcError::DuplicateNode { node_id } => {
                write!(f, "Duplicate node: {}", node_id)
            }
        }
    }
}

impl std::error::Error for HlcError {}

// Get or create HLC state for a node
fn get_or_create_hlc_state(node_id: &str) -> HlcState {
    let mut hlcs = GLOBAL_HLCS.lock().unwrap();
    hlcs.entry(node_id.to_string())
        .or_insert_with(|| HlcState::new(node_id.to_string()))
        .clone()
}

// Update HLC state for a node
fn update_hlc_state(node_id: &str, state: HlcState) {
    let mut hlcs = GLOBAL_HLCS.lock().unwrap();
    hlcs.insert(node_id.to_string(), state);
}

/// Create a new HLC timestamp at the beginning of time (Hlc.zero equivalent)
#[pg_extern]
fn hlc_zero(node_id: &str) -> HlcTimestamp {
    let state = HlcState {
        date_time: DateTime::from_timestamp(0, 0).unwrap(),
        counter: 0,
        node_id: node_id.to_string(),
    };
    update_hlc_state(node_id, state.clone());
    HlcTimestamp::from_state(&state)
}

/// Create a new HLC timestamp from a specific date (Hlc.fromDate equivalent)
#[pg_extern]
fn hlc_from_date(date_time: &str, node_id: &str) -> Result<HlcTimestamp, Box<dyn std::error::Error + Send + Sync>> {
    let dt = DateTime::parse_from_rfc3339(date_time)
        .map_err(|_| "Invalid datetime format")?;
    let dt_utc = dt.with_timezone(&Utc);

    let state = HlcState {
        date_time: dt_utc,
        counter: 0,
        node_id: node_id.to_string(),
    };
    update_hlc_state(node_id, state.clone());
    Ok(HlcTimestamp::from_state(&state))
}

/// Create a new HLC timestamp using current wall clock (Hlc.now equivalent)
#[pg_extern]
fn hlc_now(node_id: &str) -> HlcTimestamp {
    let state = HlcState {
        date_time: Utc::now(),
        counter: 0,
        node_id: node_id.to_string(),
    };
    update_hlc_state(node_id, state.clone());
    HlcTimestamp::from_state(&state)
}

/// Parse an HLC string (Hlc.parse equivalent)
#[pg_extern]
fn hlc_parse(timestamp: &str) -> Result<HlcTimestamp, Box<dyn std::error::Error + Send + Sync>> {
    HlcTimestamp::parse(timestamp)
        .map_err(|e| Box::new(std::io::Error::new(std::io::ErrorKind::InvalidInput, e)) as Box<dyn std::error::Error + Send + Sync>)
}

/// Increment the current timestamp (Hlc.increment equivalent)
#[pg_extern]
fn hlc_increment(node_id: &str, wall_time: Option<&str>) -> Result<HlcTimestamp, Box<dyn std::error::Error + Send + Sync>> {
    let mut current_state = get_or_create_hlc_state(node_id);

    // Get wall time
    let wall_time = if let Some(wt) = wall_time {
        DateTime::parse_from_rfc3339(wt)?.with_timezone(&Utc)
    } else {
        Utc::now()
    };

    // Calculate the next time and counter - matching Dart logic
    let date_time_new = if wall_time > current_state.date_time {
        wall_time
    } else {
        current_state.date_time
    };

    let counter_new = if date_time_new == current_state.date_time {
        current_state.counter + 1
    } else {
        0
    };

    // Check for drift and counter overflow - matching Dart checks
    let drift = date_time_new.signed_duration_since(wall_time);
    if drift.num_minutes() > MAX_DRIFT_MINUTES {
        return Err(Box::new(HlcError::ClockDrift {
            drift_minutes: drift.num_minutes()
        }));
    }

    if counter_new > MAX_COUNTER {
        return Err(Box::new(HlcError::Overflow { counter: counter_new }));
    }

    // Update state
    current_state.date_time = date_time_new;
    current_state.counter = counter_new;
    update_hlc_state(node_id, current_state.clone());

    Ok(HlcTimestamp::from_state(&current_state))
}

/// Merge with remote timestamp (Hlc.merge equivalent)
#[pg_extern]
fn hlc_merge(local_node_id: &str, remote: HlcTimestamp, wall_time: Option<&str>) -> Result<HlcTimestamp, Box<dyn std::error::Error + Send + Sync>> {
    let mut local_state = get_or_create_hlc_state(local_node_id);

    // Get wall time
    let wall_time = if let Some(wt) = wall_time {
        DateTime::parse_from_rfc3339(wt)?.with_timezone(&Utc)
    } else {
        Utc::now()
    };

    let remote_dt = DateTime::parse_from_rfc3339(&remote.date_time)?.with_timezone(&Utc);

    // No need to do any more work if our date + counter is same or higher
    if remote_dt < local_state.date_time ||
       (remote_dt == local_state.date_time && remote.counter <= local_state.counter) {
        return Ok(HlcTimestamp::from_state(&local_state));
    }

    // Assert the node id - matching Dart check
    if local_node_id == remote.node_id {
        return Err(Box::new(HlcError::DuplicateNode {
            node_id: local_node_id.to_string()
        }));
    }

    // Assert the remote clock drift - matching Dart check
    let drift = remote_dt.signed_duration_since(wall_time);
    if drift.num_minutes() > MAX_DRIFT_MINUTES {
        return Err(Box::new(HlcError::ClockDrift {
            drift_minutes: drift.num_minutes()
        }));
    }

    // Apply remote with local node id (matching Dart apply method)
    local_state.date_time = remote_dt;
    local_state.counter = remote.counter;
    // Keep local node_id as per Dart implementation

    update_hlc_state(local_node_id, local_state.clone());
    Ok(HlcTimestamp::from_state(&local_state))
}

/// Convert HLC timestamp to string representation
#[pg_extern]
fn hlc_to_string(hlc: HlcTimestamp) -> String {
    hlc.to_string()
}

/// Compare two HLC timestamps
#[pg_extern]
fn hlc_compare(left: HlcTimestamp, right: HlcTimestamp) -> i32 {
    match left.cmp(&right) {
        std::cmp::Ordering::Less => -1,
        std::cmp::Ordering::Equal => 0,
        std::cmp::Ordering::Greater => 1,
    }
}

/// Check if first timestamp is less than second
#[pg_extern]
fn hlc_lt(left: HlcTimestamp, right: HlcTimestamp) -> bool {
    left < right
}

/// Check if first timestamp is greater than second
#[pg_extern]
fn hlc_gt(left: HlcTimestamp, right: HlcTimestamp) -> bool {
    left > right
}

/// Check if timestamps are equal
#[pg_extern]
fn hlc_eq(left: HlcTimestamp, right: HlcTimestamp) -> bool {
    left == right
}

/// Check if first timestamp is less than or equal to second
#[pg_extern]
fn hlc_lte(left: HlcTimestamp, right: HlcTimestamp) -> bool {
    left <= right
}

/// Check if first timestamp is greater than or equal to second
#[pg_extern]
fn hlc_gte(left: HlcTimestamp, right: HlcTimestamp) -> bool {
    left >= right
}

/// Reset HLC state for a node (useful for testing)
#[pg_extern]
fn hlc_reset(node_id: &str) {
    let mut hlcs = GLOBAL_HLCS.lock().unwrap();
    hlcs.remove(node_id);
}

/// Get current state of an HLC node
#[pg_extern]
fn hlc_get_state(node_id: &str) -> HlcTimestamp {
    let state = get_or_create_hlc_state(node_id);
    HlcTimestamp::from_state(&state)
}

// SQL-compatible wrapper functions with simpler interfaces

/// Simplified increment function for SQL (no optional wall_time parameter)
#[pg_extern]
fn hlc_increment_simple(node_id: &str) -> HlcTimestamp {
    hlc_increment(node_id, None).unwrap_or_else(|_| hlc_now(node_id))
}

/// Simplified merge function for SQL (no optional wall_time parameter)
#[pg_extern]
fn hlc_merge_simple(local_node_id: &str, remote: HlcTimestamp) -> HlcTimestamp {
    hlc_merge(local_node_id, remote, None).unwrap_or_else(|_| hlc_now(local_node_id))
}
