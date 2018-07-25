view: names {
  sql_table_name: `fh-bigquery.popular_names.usa_1910_2013`
    ;;

  dimension: name {}
  dimension: state {}
  dimension: gender {}
  dimension: year {type:number}
  dimension: number {type:number sql: CAST(${TABLE}.number AS FLOAT64) ;;}

  dimension: decade {
    type: number
    sql: CAST(FLOOR(${year}/10)*10 AS INT64) ;;
  }

  measure: total_number {
    type: sum
    sql: ${number} ;;
    drill_fields: [name, state, year, name, number]
  }

  measure: names_count {
    type: count_distinct
    sql: ${name} ;;
    drill_fields: [name, total_number]
  }

  measure: median_year {
    type: number
    sql: MEDIAN_WEIGHTED(ARRAY_AGG(STRUCT(CAST(${year} as FLOAT64) as num, ${number} as weight)));;
  }

  measure: top_5_names {
    type: string
    sql: pairs_sum_top_n(ARRAY_AGG(STRUCT(${name} as key, ${number} as value)), 5) ;;
  }

  measure: decade_graph {
    type: string
    sql: time_graph(ARRAY_AGG(STRUCT(CAST(${decade} AS STRING) as key, ${number} as value)),10) ;;
    html:
     <img src="https://chart.googleapis.com/chart?chs=200x50&cht=ls&chco=0077CC&chf=bg,s,FFFFFF00&chxt=x&chxr=0,1910,2010,20&chd=t:{{value}}">
    ;;
  }
}
