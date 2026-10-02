(ns notebook.security
  (:require [next.jdbc :as jdbc]
            [notebook.db :as db]))

(defn -main [& _]
  (with-open [operational (db/pool "notebook_app" (db/required "NOTEBOOK_APP_PASSWORD") 2 "security-operational")
              reporting (db/pool "notebook_report" (db/required "NOTEBOOK_REPORT_PASSWORD") 1 "security-reporting")]
    (doseq [[source role statement lock] [[operational "notebook_app" "5s" "2s"]
                                        [reporting "notebook_report" "12s" "2s"]]]
      (let [result (jdbc/execute-one! source
                     ["SELECT current_user AS role,current_setting('statement_timeout') AS statement,
                              current_setting('lock_timeout') AS lock,current_schemas(false)::text AS schemas,
                              ssl,version AS tls FROM pg_stat_ssl WHERE pid=pg_backend_pid()"] db/options)]
        (assert (= role (:role result)))
        (assert (= statement (:statement result)))
        (assert (= lock (:lock result)))
        (assert (:ssl result))
        (when (= role "notebook_app") (assert (= "{notebook,pg_catalog}" (:schemas result))))
        (println result)))))
