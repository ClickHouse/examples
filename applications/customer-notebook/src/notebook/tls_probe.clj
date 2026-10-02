(ns notebook.tls-probe
  (:require [clojure.string :as str]
            [next.jdbc :as jdbc]
            [notebook.db :as db]))

(defn -main [& _]
  (with-open [source (db/pool "notebook_app" (db/required "NOTEBOOK_APP_PASSWORD") 1 "tls-control")]
    (try
      (jdbc/execute-one! source ["SELECT 1"])
      (assert (nil? (System/getenv "EXPECTED_TLS_FAILURE")))
      (println "Same runtime factory positive verified TLS query passed.")
      (catch java.sql.SQLException error
        (let [causes (take-while some? (iterate #(.getCause ^Throwable %) error))
              description (str/join " " (map #(.getMessage ^Throwable %) causes))
              expected (System/getenv "EXPECTED_TLS_FAILURE")]
          (assert (case expected
                    "ca" (boolean (re-find #"(?i)PKIX|certification path|trust anchor" description))
                    "hostname" (boolean (re-find #"(?i)hostname.*(verified|verify)|verify.*hostname" description))
                    false))
          ;; Only exception classes are emitted; messages can contain private DNS.
          (println "Runtime factory TLS negative" expected "SQLState" (.getSQLState error)
                   "causes" (mapv #(.getName (class %)) causes)))))))
