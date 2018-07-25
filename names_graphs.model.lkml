connection: "bigquery_publicdata"
include: "*.view.lkml"
explore: names {
  extends: [custom_functions]
  persist_for: "24 hours"
}
