-- Minimal test of pg_hlc extension
-- Load the extension library
CREATE OR REPLACE FUNCTION test_extension_load()
RETURNS text
AS '$libdir/pg_hlc', 'test_function'
LANGUAGE C;
