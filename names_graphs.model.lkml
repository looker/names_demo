connection: "bigquery_publicdata_standard_sql"
include: "*.view.lkml"
explore: names {
  extends: [custom_functions]
  persist_for: "24 hours"
}
