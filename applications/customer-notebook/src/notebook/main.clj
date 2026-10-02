(ns notebook.main
  (:gen-class)
  (:require [notebook.db :as db]
            [notebook.http :as http]
            [ring.adapter.jetty :as jetty]))

(defn -main [& _]
  (let [operational (db/pool "notebook_app" (db/required "NOTEBOOK_APP_PASSWORD") 2 "notebook-operational")
        reporting (db/pool "notebook_report" (db/required "NOTEBOOK_REPORT_PASSWORD") 1 "notebook-reporting")]
    (try
      (let [server (jetty/run-jetty (http/handler operational reporting)
                     {:host "127.0.0.1" :port 8080 :join? false
                      :min-threads 2 :max-threads 16 :max-idle-time 15000})]
        (.addShutdownHook (Runtime/getRuntime)
          (Thread. (fn [] (.stop server) (.close reporting) (.close operational))))
        (println "Customer notebook listening on http://127.0.0.1:8080")
        (.join server))
      (catch Exception error
        (.close reporting)
        (.close operational)
        (throw error)))))
