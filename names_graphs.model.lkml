connection: "bigquery_publicdata_standard_sql"
include: "*.view.lkml"
explore: grapefruit {
  view_name: names
  persist_for: "24 hours"
}
