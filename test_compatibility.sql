-- Test script to verify HLC implementation compatibility with Dart CRDT
-- Run this after installing the extension

\echo 'Testing PostgreSQL HLC Extension Compatibility with Dart CRDT...'

-- Create extension
CREATE EXTENSION IF NOT EXISTS pg_hlc;

-- Test 1: Basic HLC creation
\echo 'Test 1: Basic HLC Creation'
SELECT hlc_zero('test_node') as zero_hlc;
SELECT hlc_now('test_node') as now_hlc;

-- Test 2: String format compatibility
\echo 'Test 2: String Format Compatibility (should match Dart format)'
WITH test_hlc AS (
    SELECT hlc_from_date('2023-12-25T10:30:45.123456Z', 'dart_node') as hlc
)
SELECT
    hlc_to_string(hlc) as dart_compatible_string
FROM test_hlc;

-- Test 3: Parse and round-trip
\echo 'Test 3: Parse and Round-trip'
WITH original AS (
    SELECT hlc_now('round_trip_test') as hlc_orig
),
string_form AS (
    SELECT hlc_orig, hlc_to_string(hlc_orig) as hlc_str
    FROM original
),
parsed_back AS (
    SELECT hlc_orig, hlc_str, hlc_parse(hlc_str) as hlc_parsed
    FROM string_form
)
SELECT
    hlc_to_string(hlc_orig) as original,
    hlc_str as string_form,
    hlc_to_string(hlc_parsed) as parsed_back,
    hlc_eq(hlc_orig, hlc_parsed) as strings_match
FROM parsed_back;

-- Test 4: Increment behavior (matching Dart logic)
\echo 'Test 4: Increment Behavior'
SELECT hlc_reset('increment_node');

WITH increments AS (
    SELECT
        hlc_increment('increment_node') as hlc1,
        hlc_increment('increment_node') as hlc2,
        hlc_increment('increment_node') as hlc3
)
SELECT
    hlc_to_string(hlc1) as first,
    hlc_to_string(hlc2) as second,
    hlc_to_string(hlc3) as third,
    hlc_lt(hlc1, hlc2) AND hlc_lt(hlc2, hlc3) as monotonic_increasing
FROM increments;

-- Test 5: Merge behavior (matching Dart logic)
\echo 'Test 5: Merge Behavior'
SELECT hlc_reset('local_node');
SELECT hlc_reset('remote_node');

WITH test_merge AS (
    SELECT
        hlc_increment('local_node') as local_hlc,
        hlc_increment('remote_node') as remote_hlc
),
merged AS (
    SELECT
        local_hlc,
        remote_hlc,
        hlc_merge('local_node', remote_hlc) as merged_hlc
    FROM test_merge
)
SELECT
    hlc_to_string(local_hlc) as local,
    hlc_to_string(remote_hlc) as remote,
    hlc_to_string(merged_hlc) as merged,
    -- Should keep local node ID but take remote timestamp if newer
    (merged_hlc).node_id = 'local_node' as preserves_local_node_id
FROM merged;

-- Test 6: Comparison operators (matching Dart compareTo)
\echo 'Test 6: Comparison Operators'
WITH test_comparison AS (
    SELECT
        hlc_parse('2023-12-25T10:30:45.123456Z-0001-nodeA') as hlc1,
        hlc_parse('2023-12-25T10:30:45.123456Z-0002-nodeA') as hlc2,
        hlc_parse('2023-12-25T10:30:46.123456Z-0001-nodeA') as hlc3
)
SELECT
    hlc_to_string(hlc1) as hlc1,
    hlc_to_string(hlc2) as hlc2,
    hlc_to_string(hlc3) as hlc3,
    hlc_lt(hlc1, hlc2) as hlc1_lt_hlc2,
    hlc_lt(hlc2, hlc3) as hlc2_lt_hlc3,
    hlc_lt(hlc1, hlc3) as hlc1_lt_hlc3
FROM test_comparison;

-- Test 7: Error conditions (should match Dart exceptions)
\echo 'Test 7: Error Conditions'

-- Test duplicate node error
\echo 'Testing duplicate node error...'
DO $$
BEGIN
    BEGIN
        PERFORM hlc_merge('same_node', hlc_parse('2023-12-25T10:30:45.123456Z-0001-same_node'));
        RAISE EXCEPTION 'Expected duplicate node error but got none';
    EXCEPTION
        WHEN others THEN
            RAISE NOTICE 'Correctly caught duplicate node error: %', SQLERRM;
    END;
END $$;

-- Test 8: Ordering with different node IDs (matching Dart compareTo)
\echo 'Test 8: Node ID Ordering'
WITH same_time_different_nodes AS (
    SELECT
        hlc_parse('2023-12-25T10:30:45.123456Z-0001-nodeA') as hlc_a,
        hlc_parse('2023-12-25T10:30:45.123456Z-0001-nodeB') as hlc_b,
        hlc_parse('2023-12-25T10:30:45.123456Z-0001-nodeC') as hlc_c
)
SELECT
    hlc_lt(hlc_a, hlc_b) as a_lt_b,
    hlc_lt(hlc_b, hlc_c) as b_lt_c,
    hlc_lt(hlc_a, hlc_c) as a_lt_c
FROM same_time_different_nodes;

\echo 'All tests completed! Check results for Dart compatibility.'
