-- pg_hlc extension installation script
-- Version: 0.1.0

-- HLC timestamp type with input/output functions
CREATE TYPE hlctimestamp;

-- Core HLC functions
CREATE OR REPLACE FUNCTION hlc_zero(text)
RETURNS hlctimestamp
AS 'MODULE_PATHNAME', 'hlc_zero'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_now(text)
RETURNS hlctimestamp
AS 'MODULE_PATHNAME', 'hlc_now'
LANGUAGE C VOLATILE STRICT;

-- Use simplified wrapper functions for SQL interface
CREATE OR REPLACE FUNCTION hlc_increment(text)
RETURNS hlctimestamp
AS 'MODULE_PATHNAME', 'hlc_increment_simple'
LANGUAGE C VOLATILE STRICT;

CREATE OR REPLACE FUNCTION hlc_merge(text, hlctimestamp)
RETURNS hlctimestamp
AS 'MODULE_PATHNAME', 'hlc_merge_simple'
LANGUAGE C VOLATILE STRICT;

CREATE OR REPLACE FUNCTION hlc_from_date(text, text)
RETURNS hlctimestamp
AS 'MODULE_PATHNAME', 'hlc_from_date'
LANGUAGE C IMMUTABLE;

-- String conversion functions
CREATE OR REPLACE FUNCTION hlc_to_string(hlctimestamp)
RETURNS text
AS 'MODULE_PATHNAME', 'hlc_to_string'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_parse(text)
RETURNS hlctimestamp
AS 'MODULE_PATHNAME', 'hlc_parse'
LANGUAGE C IMMUTABLE STRICT;

-- Comparison functions
CREATE OR REPLACE FUNCTION hlc_compare(hlctimestamp, hlctimestamp)
RETURNS integer
AS 'MODULE_PATHNAME', 'hlc_compare'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_eq(hlctimestamp, hlctimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_ne(hlctimestamp, hlctimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_ne'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_lt(hlctimestamp, hlctimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_lt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_lte(hlctimestamp, hlctimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_lte'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_gt(hlctimestamp, hlctimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_gt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION hlc_gte(hlctimestamp, hlctimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_gte'
LANGUAGE C IMMUTABLE STRICT;

-- Utility functions
CREATE OR REPLACE FUNCTION hlc_reset(text)
RETURNS boolean
AS 'MODULE_PATHNAME', 'hlc_reset'
LANGUAGE C VOLATILE STRICT;

-- Define operators for HLC comparison
CREATE OPERATOR = (
    LEFTARG = hlctimestamp,
    RIGHTARG = hlctimestamp,
    FUNCTION = hlc_eq,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel,
    JOIN = eqjoinsel,
    HASHES, MERGES
);

CREATE OPERATOR <> (
    LEFTARG = hlctimestamp,
    RIGHTARG = hlctimestamp,
    FUNCTION = hlc_ne,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel,
    JOIN = neqjoinsel
);

CREATE OPERATOR < (
    LEFTARG = hlctimestamp,
    RIGHTARG = hlctimestamp,
    FUNCTION = hlc_lt,
    COMMUTATOR = '>',
    NEGATOR = '>=',
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);

CREATE OPERATOR <= (
    LEFTARG = hlctimestamp,
    RIGHTARG = hlctimestamp,
    FUNCTION = hlc_lte,
    COMMUTATOR = '>=',
    NEGATOR = '>',
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);

CREATE OPERATOR > (
    LEFTARG = hlctimestamp,
    RIGHTARG = hlctimestamp,
    FUNCTION = hlc_gt,
    COMMUTATOR = '<',
    NEGATOR = '<=',
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);

CREATE OPERATOR >= (
    LEFTARG = hlctimestamp,
    RIGHTARG = hlctimestamp,
    FUNCTION = hlc_gte,
    COMMUTATOR = '<=',
    NEGATOR = '<',
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);

-- Create B-tree operator class for indexing
CREATE OPERATOR CLASS hlctimestamp_ops
DEFAULT FOR TYPE hlctimestamp USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 hlc_compare(hlctimestamp, hlctimestamp);
