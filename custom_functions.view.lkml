explore: custom_functions {
  extends: [cf_empty, url_functions, pair_functions, misc_functions, math_functions]
  hidden: yes
  extension: required
}

# must be the first function in the list.
explore: cf_empty {
  extension: required
  sql_preamble:  --
    ;;
}

explore: math_functions {
  extension: required
  extends: [math_functions_median, math_functions_median_weighted]
}

explore: math_functions_median {
  extension: required
  #
  #  Median function, returns the median of an array of FLOAT64
  #
  #   USAGE:  SELECT MEDIAN(ARRAY_AGG(num)) FROM ...
  #
  sql_preamble:
    ${EXTENDED}
     -- math functions
    CREATE TEMP FUNCTION MEDIAN(a_num ARRAY<FLOAT64>)
    RETURNS FLOAT64 AS ((
       SELECT
          AVG(num)
        FROM (
          SELECT
            row_number() OVER (ORDER BY num) -1 as rn
            , num
          FROM UNNEST(a_num) num
        )
        WHERE
          rn = TRUNC(ARRAY_LENGTH(a_num)/2)
            OR (
             MOD(ARRAY_LENGTH(a_num), 2) = 0 AND
              rn = TRUNC(ARRAY_LENGTH(a_num)/2)-1 )
    ));
  ;;
}

explore: math_functions_median_weighted {
  extension: required
  #
  #  Median function, returns the median of an array of FLOAT64
  #
  #   USAGE:  SELECT MEDIAN(ARRAY_AGG(num)) FROM ...
  #
  sql_preamble:
    ${EXTENDED}
     -- math functions

      CREATE TEMP FUNCTION _pairs_sum_float(a ARRAY<STRUCT<num FLOAT64, weight FLOAT64>>)
      RETURNS ARRAY<STRUCT<num FLOAT64, weight FLOAT64>> AS ((
        SELECT
           ARRAY_AGG(STRUCT(num,weight))
        FROM (
          SELECT
            num
            , SUM(weight) as weight
          FROM UNNEST(a)
          GROUP BY 1
          ORDER BY 2 DESC
        )
      ));


      CREATE TEMP FUNCTION MEDIAN_WEIGHTED(a_nums ARRAY<STRUCT<num FLOAT64, weight FLOAT64>>)
      RETURNS FLOAT64 AS ((
        SELECT
          num
        FROM (
         SELECT
            MAX(cumulative_weight) OVER() max_weight
            , cumulative_weight
            , num
          FROM (
            SELECT
              SUM(num) OVER (ORDER BY num) as cumulative_weight
              , weight
              , num
            FROM UNNEST(_pairs_sum_float(a_nums)) a
            ORDER BY num
          )
        )
        WHERE cumulative_weight > max_weight/2
        ORDER BY num
        LIMIT 1
    ));
  ;;
}

explore: misc_functions {
  extension: required
  sql_preamble:
    ${EXTENDED}
     -- miscelaneous functions
    CREATE TEMP FUNCTION COUNT_DISTINCT_ARRAY(s ARRAY<STRING>)
    RETURNS INT64 AS ((
      SELECT COUNT(DISTINCT x) FROM UNNEST(s) as x
    ));

    CREATE TEMP FUNCTION STRING_AGG_DISTINCT(s ARRAY<STRING>)
    RETURNS STRING AS ((
      SELECT STRING_AGG(x,', ')
      FROM (
        SELECT x
        FROM UNNEST(s) as x
        WHERE x <> ''
        GROUP BY 1 ORDER BY 1

      )
    ));

    CREATE TEMP FUNCTION GET_VIS_PARAM(query STRING, p STRING)
    RETURNS STRING
    LANGUAGE js AS """
      ret = null
      try {
        if(query) {
          params = query.split("&").forEach(function(part){
            item  = part.split('=')
            if(item[0] == 'vis' ) {
              ret = JSON.parse(decodeURIComponent(item[1]))[p]
            }
          });
        }
      }
      catch(err){}
      return ret
    """;

      -- Build a decade graph
      CREATE TEMP FUNCTION time_graph(a ARRAY<STRUCT<key STRING, value FLOAT64>>, t INT64)
      RETURNS STRING AS ((
        SELECT
           STRING_AGG(COALESCE(FORMAT("%0.0f",value),"0"))
        FROM (
          SELECT
            *
          FROM
            UNNEST(GENERATE_ARRAY(1910,2013,t)) AS year
            -- zero fill the decades with no data.
            LEFT JOIN UNNEST(pairs_convert_percentage(pairs_sum(a),'max')) as d
              ON d.key=CAST(year as STRING)
          ORDER BY year
        )
      ));

      CREATE TEMP FUNCTION pairs_count_distinct(a ARRAY<STRUCT<key STRING, value STRING>>)
      RETURNS ARRAY<STRUCT<key STRING, value FLOAT64>> AS ((
        SELECT
          ARRAY_AGG(STRUCT(key, value))
        FROM (
           SELECT
              key, CAST(COUNT(*) as FLOAT64) as value
              FROM (
                SELECT
                  a.key, a.value
                FROM UNNEST(a) a
                GROUP BY 1,2
              )
              GROUP BY 1
           )
      ));

      CREATE TEMP FUNCTION list_top_n( a ARRAY<STRUCT<key STRING, value STRING>>, n INT64)
      RETURNS STRING AS ((
        pairs_to_string(
          pairs_top_n(
            pairs_count_distinct(a)
            , n
            , false
          ),'decimal_0'
         )
      ));
  ;;
}


# These functions all work with array of string/numbers and do various forms of transformation
#  used to compute top N, distinct sums and values, weighted ordered lists, and the core of
#  dynamic graphing.
#
explore: pair_functions{
  extension: required
  sql_preamble:
    -- pair functions
    ${EXTENDED}
     -- take a dimension, number pair and aggregate as a sum
      CREATE TEMP FUNCTION pairs_sum(a ARRAY<STRUCT<key STRING, value FLOAT64>>)
      RETURNS ARRAY<STRUCT<key STRING, value FLOAT64>> AS ((
        SELECT
           ARRAY_AGG(STRUCT(key,total_value as value))
        FROM (
          SELECT
            key
            , SUM(value) as total_value
          FROM UNNEST(a)
          GROUP BY 1
          ORDER BY 2 DESC
        )
      ));

      -- take a set of string, number pairs and convert the number to percentage of max or total
      -- pass 'total' or 'max' as type to change behaviour
      CREATE TEMP FUNCTION pairs_convert_percentage(a ARRAY<STRUCT<key STRING, value FLOAT64>>,type STRING)
      RETURNS ARRAY<STRUCT<key STRING, value FLOAT64>> AS ((
        SELECT
          ARRAY_AGG(STRUCT(key,new_value as value))
        FROM (
          SELECT
            key
            , 100.0*value/total
             as new_value
          FROM UNNEST(a)
          CROSS JOIN (
            SELECT
              CASE
               WHEN type='total' THEN SUM(b.value)
               WHEN type='max' THEN MAX(b.value)
              END
              as total FROM UNNEST(a) as b
          ) as t
          ORDER BY 2 DESC
        )
      ));

      -- formats a STR N into String(number)
      CREATE TEMP FUNCTION format_result(key STRING, value FLOAT64, format_str STRING)
      RETURNS STRING AS ((
        SELECT
           CONCAT(key, '(',
            CASE
              WHEN format_str = 'decimal_0'
                THEN FORMAT("%0.0f", value)
              WHEN format_str = 'percent_0'
                THEN FORMAT("%0.2f%%", value)
            END,
            ')' )
      ));

      -- convert pairs into a string ('Other' is always last)
      CREATE TEMP FUNCTION pairs_to_string(a ARRAY<STRUCT<key STRING, value FLOAT64>>, format_str STRING)
      RETURNS STRING AS ((
        SELECT
          STRING_AGG(value2,", ")
        FROM (
          SELECT (
            format_result(key,value,format_str)) as value2
            ,rn
          FROM (
            SELECT
              ROW_NUMBER() OVER (ORDER BY CASE WHEN key='Other' THEN -1 ELSE value END DESC) as rn
              , *
            FROM
              UNNEST(a)
          )
          ORDER BY rn
        )
      ));

      -- convert a array to a shortened array with an 'Other'.  Keep the ordering by Num and make other last
      --  by using a row number.
      CREATE TEMP FUNCTION pairs_top_n(a ARRAY<STRUCT<key STRING, value FLOAT64>>, n INT64, use_other BOOL)
      RETURNS ARRAY<STRUCT<key STRING, value FLOAT64>> AS ((
        SELECT
          ARRAY(
            SELECT
              STRUCT(key2 as key ,value2 as value)
            FROM (
              SELECT
                CASE WHEN rn <= n THEN key ELSE 'Other' END as key2
                , CASE WHEN rn <= n THEN n ELSE n + 1 END as n2
                , SUM(value) as value2
              FROM (
                SELECT
                  ROW_NUMBER() OVER() as rn
                  , *
                FROM UNNEST(a)
                ORDER BY value DESC
              )
              GROUP BY 1,2
              ORDER BY 2
            ) as t
            WHERE key2 <> 'Other' or use_other
            ORDER BY n2
          )
      ));


      -- convert pairs to a json string
      CREATE TEMP FUNCTION pairs_to_json(a ARRAY<STRUCT<key STRING, value FLOAT64>>)
      RETURNS STRING
      LANGUAGE js AS """
        return JSON.stringify(a);
      """;

      -- take pairs, sum them and convert to a string
      CREATE TEMP FUNCTION pairs_sum_str(a ARRAY<STRUCT<key STRING, value FLOAT64>>)
      RETURNS STRING AS ((
         pairs_to_string( pairs_sum(a), 'decimal_0' )
      ));

      -- take pairs them sum and convert to a json blob
      CREATE TEMP FUNCTION pairs_sum_graph(a ARRAY<STRUCT<key STRING, value FLOAT64>>)
      RETURNS STRING AS ((
        SELECT
           CONCAT('chl=',STRING_AGG(key,'|'),'&chd=t:',STRING_AGG(FORMAT("%0.0f",value),','))
        FROM (SELECT * FROM UNNEST(pairs_convert_percentage(pairs_sum(a),'total')) ORDER BY key)
      ));

      -- take pairs sum, topn then and convert to a string
      CREATE TEMP FUNCTION pairs_sum_top_n(a ARRAY<STRUCT<key STRING, value FLOAT64>>, n INT64)
      RETURNS STRING AS ((
        pairs_to_string( pairs_top_n(pairs_convert_percentage(pairs_sum(a),'total'), n, true), 'percent_0' )
      ));

    ;;
}


explore: url_functions {
  extension: required
  sql_preamble:
    ${EXTENDED}
    -- url functions

    CREATE TEMP FUNCTION GET_URL_PARAM(query STRING, p STRING)
    RETURNS STRING
    LANGUAGE js AS """
      ret = null
      try{
        if(query) {
          params = query.split("&").forEach(function(part){
            item  = part.split('=')
            if(item[0] == p ) {
              ret = decodeURIComponent(item[1])
            }
          });
        }
      }
      catch(err){}
      return ret
    """;

    CREATE TEMP FUNCTION GET_URL_KEYS(query STRING)
    RETURNS ARRAY<STRING>
    LANGUAGE js AS """
      ret = []
      try{
        if(query) {
          params = query.split("&").forEach(function(part){
            ret.push( part.split('=')[0] )
          });
        }
      }
      catch(err){}
      return ret
    """;
  ;;
}
