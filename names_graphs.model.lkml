connection: "bigquery_publicdata_standard_sql"
include: "*.view.lkml"
explore: names {
  hidden: yes
  extends: [custom_functions]
  persist_for: "24 hours"
}

view: names {
  sql_table_name: `fh-bigquery.popular_names.usa_1910_2013`
    ;;

  dimension: name {}
  dimension: state {}
  dimension: gender {}
  dimension: year {type:number}

  dimension: decade {
    type: number
    sql: CAST(FLOOR(${year}/10)*10 AS INT64) ;;
  }

  dimension: first_letter {
    sql: SUBSTR(${name},1,1) ;;
  }

  dimension: number {
    type: number
    sql: CAST(${TABLE}.number AS FLOAT64) ;;
  }

  measure: total_number {
    type: sum
    sql: ${number} ;;
    drill_fields: [name, state, year, name, number]
  }

  measure: gender_balance {
    type: string
    sql:  pairs_sum_str(ARRAY_AGG(STRUCT(${gender} as key, ${number} as value)))  ;;
  }

  measure: gender_balance_graph {
    type: string
    sql:  pairs_sum_graph(ARRAY_AGG(STRUCT(${gender} as key, ${number} as value)))  ;;
    html:
    <img src="https://chart.googleapis.com/chart?chs=200x50&cht=p3&chf=bg,s,FFFFFF00&{{value}}">
    ;;
  }

  measure: top_5_names {
    type: string
    sql: pairs_sum_top_n(ARRAY_AGG(STRUCT(${name} as key, ${number} as value)), 5) ;;
  }

  measure: top_3_years {
    type: string
    sql: pairs_sum_top_n(ARRAY_AGG(STRUCT(CAST(${year} as STRING) as key, ${number} as value)), 3) ;;
  }

  measure: top_5_states {
    type: string
    sql: pairs_sum_top_n(ARRAY_AGG(STRUCT(${state} as key, ${number} as value)), 5) ;;
  }

  measure: median_year {
    type: number
    sql: MEDIAN_WEIGHTED(ARRAY_AGG(STRUCT(CAST(${year} as FLOAT64) as num, ${number} as weight)));;
  }

  measure: decade_graph {
    type: string
    sql: time_graph(ARRAY_AGG(STRUCT(CAST(${decade} AS STRING) as key, ${number} as value)),10) ;;
    html:
     <img src="https://chart.googleapis.com/chart?chs=200x50&cht=ls&chco=0077CC&chf=bg,s,FFFFFF00&chxt=x&chxr=0,1910,2010,20&chd=t:{{value}}">
    ;;
  }

  measure: year_graph {
    type: string
    sql: time_graph(ARRAY_AGG(STRUCT(CAST(${year} AS STRING) as key, ${number} as value)),1) ;;
    html:
    <img src="https://chart.googleapis.com/chart?chs=200x50&cht=ls&chco=0077CC&chxt=x&chxr=0,1910,2013,20&chf=bg,s,FFFFFF00&chd=t:{{value}}">
    ;;

  }
}
