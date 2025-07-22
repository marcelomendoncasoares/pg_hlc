-- PostgreSQL HLC Extension Examples
-- This file demonstrates usage of the pg_hlc extension

-- Create the extension
CREATE EXTENSION IF NOT EXISTS pg_hlc;

-- Example 1: Basic HLC operations
SELECT 'Basic HLC Operations' as example;

-- Create HLC timestamps
SELECT hlc_zero('node1') as zero_hlc;
SELECT hlc_now('node1') as current_hlc;
SELECT hlc_from_date('2023-12-25T10:30:45.123456Z', 'node1') as date_hlc;

-- Example 2: HLC increment behavior
SELECT 'HLC Increment Behavior' as example;

-- Reset node state
SELECT hlc_reset('increment_test');

-- Generate sequence of HLCs
SELECT hlc_increment('increment_test') as hlc1;
SELECT hlc_increment('increment_test') as hlc2;
SELECT hlc_increment('increment_test') as hlc3;

-- Example 3: String parsing and formatting
SELECT 'String Parsing and Formatting' as example;

-- Create HLC and convert to string
WITH hlc_example AS (
    SELECT hlc_now('string_test') as hlc_ts
)
SELECT
    hlc_ts,
    hlc_to_string(hlc_ts) as string_repr,
    hlc_parse(hlc_to_string(hlc_ts)) as parsed_back
FROM hlc_example;

-- Example 4: HLC comparisons
SELECT 'HLC Comparisons' as example;

-- Reset and create test timestamps
SELECT hlc_reset('compare_test');

WITH test_hlcs AS (
    SELECT
        hlc_increment('compare_test') as hlc1,
        hlc_increment('compare_test') as hlc2
)
SELECT
    hlc1, hlc2,
    hlc_compare(hlc1, hlc2) as compare_result,
    hlc_lt(hlc1, hlc2) as is_less_than,
    hlc_gt(hlc1, hlc2) as is_greater_than,
    hlc_eq(hlc1, hlc2) as is_equal,
    hlc_lte(hlc1, hlc2) as is_less_or_equal,
    hlc_gte(hlc1, hlc2) as is_greater_or_equal
FROM test_hlcs;

-- Example 5: Distributed system simulation
SELECT 'Distributed System Simulation' as example;

-- Reset nodes
SELECT hlc_reset('node_a');
SELECT hlc_reset('node_b');

-- Node A generates events
WITH node_a_events AS (
    SELECT hlc_increment('node_a') as event1,
           hlc_increment('node_a') as event2
),
-- Node B receives Node A's event2 and merges
node_b_merge AS (
    SELECT hlc_merge('node_b', event2) as merged_hlc
    FROM node_a_events
),
-- Node B continues with its own events
node_b_events AS (
    SELECT
        merged_hlc,
        hlc_increment('node_b') as event3,
        hlc_increment('node_b') as event4
    FROM node_b_merge
)
SELECT * FROM node_b_events;

-- Example 6: Table with HLC timestamps
SELECT 'Table with HLC Timestamps' as example;

-- Create a distributed events table
CREATE TABLE IF NOT EXISTS distributed_events (
    id SERIAL PRIMARY KEY,
    event_type TEXT,
    event_data JSONB,
    node_id TEXT,
    hlc_timestamp hlctimestamp,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert events from different nodes
INSERT INTO distributed_events (event_type, event_data, node_id, hlc_timestamp)
VALUES
    ('user_login', '{"user_id": 123, "ip": "192.168.1.1"}', 'web_server_1', hlc_increment('web_server_1')),
    ('user_action', '{"user_id": 123, "action": "view_page", "page": "/dashboard"}', 'web_server_1', hlc_increment('web_server_1')),
    ('user_login', '{"user_id": 456, "ip": "192.168.1.2"}', 'web_server_2', hlc_increment('web_server_2')),
    ('data_sync', '{"table": "users", "records": 100}', 'db_sync_1', hlc_increment('db_sync_1'));

-- Query events in HLC order (causal order)
SELECT
    event_type,
    event_data,
    node_id,
    hlc_to_string(hlc_timestamp) as hlc_string,
    created_at
FROM distributed_events
ORDER BY hlc_timestamp;

-- Example 7: HLC merge operations in practice
SELECT 'HLC Merge Operations' as example;

-- Simulate receiving events from remote nodes
WITH remote_events AS (
    SELECT hlc_parse('2023-12-25T10:30:45.123456Z-0005-remote_node_1') as remote_hlc1,
           hlc_parse('2023-12-25T10:30:46.789012Z-0002-remote_node_2') as remote_hlc2
),
local_merges AS (
    SELECT
        hlc_merge('local_node', remote_hlc1) as merged1,
        hlc_merge('local_node', remote_hlc2) as merged2
    FROM remote_events
)
SELECT
    hlc_to_string(merged1) as after_merge1,
    hlc_to_string(merged2) as after_merge2,
    hlc_to_string(hlc_increment('local_node')) as local_next_event
FROM local_merges;

-- Example 8: Range queries with HLC
SELECT 'Range Queries with HLC' as example;

-- Find all events between two HLC timestamps
WITH hlc_range AS (
    SELECT
        hlc_parse('2023-12-25T10:30:45.000000Z-0000-any_node') as start_hlc,
        hlc_parse('2023-12-25T10:30:46.000000Z-FFFF-any_node') as end_hlc
)
SELECT
    event_type,
    node_id,
    hlc_to_string(hlc_timestamp) as hlc_string
FROM distributed_events, hlc_range
WHERE hlc_timestamp >= start_hlc
  AND hlc_timestamp <= end_hlc
ORDER BY hlc_timestamp;

-- Example 9: Conflict resolution using HLC
SELECT 'Conflict Resolution using HLC' as example;

-- Simulate concurrent updates to the same resource
CREATE TABLE IF NOT EXISTS resource_updates (
    resource_id TEXT,
    update_data JSONB,
    node_id TEXT,
    hlc_timestamp hlctimestamp,
    PRIMARY KEY (resource_id, hlc_timestamp)
);

-- Insert conflicting updates
INSERT INTO resource_updates (resource_id, update_data, node_id, hlc_timestamp)
VALUES
    ('resource_123', '{"field": "value_a", "user": "alice"}', 'node_1', hlc_increment('node_1')),
    ('resource_123', '{"field": "value_b", "user": "bob"}', 'node_2', hlc_increment('node_2')),
    ('resource_123', '{"field": "value_c", "user": "charlie"}', 'node_3', hlc_increment('node_3'));

-- Resolve conflicts by taking the latest HLC timestamp
SELECT DISTINCT ON (resource_id)
    resource_id,
    update_data as winning_update,
    node_id as winning_node,
    hlc_to_string(hlc_timestamp) as winning_hlc
FROM resource_updates
ORDER BY resource_id, hlc_timestamp DESC;

-- Example 10: Performance and indexing
SELECT 'Performance and Indexing' as example;

-- Create index on HLC timestamp for efficient ordering
CREATE INDEX IF NOT EXISTS idx_events_hlc ON distributed_events USING btree(hlc_timestamp);

-- Analyze query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM distributed_events
ORDER BY hlc_timestamp
LIMIT 10;

-- Clean up examples
DROP TABLE IF EXISTS distributed_events;
DROP TABLE IF EXISTS resource_updates;
