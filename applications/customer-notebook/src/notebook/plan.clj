(ns notebook.plan
  (:require [next.jdbc :as jdbc]
            [notebook.db :as db])
  (:import (java.util UUID)
           (java.time LocalDate)))

(defn -main [& _]
  (with-open [source (db/pool "notebook_report" (db/required "NOTEBOOK_REPORT_PASSWORD") 1 "exact-report-plan")]
    (doseq [row (jdbc/execute! source
                 [(str "EXPLAIN(VERBOSE,COSTS OFF) " db/activity-sql)
                  (UUID/fromString "00000000-0000-0000-0000-000000000001")
                  (LocalDate/parse "2026-09-28") (LocalDate/parse "2026-09-30")]
                 db/options)]
      (println (get row (keyword "query plan"))))))
