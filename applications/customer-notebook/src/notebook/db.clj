(ns notebook.db
  (:require [next.jdbc :as jdbc]
            [next.jdbc.result-set :as rs])
  (:import (com.zaxxer.hikari HikariConfig HikariDataSource)
           (org.postgresql.ds PGSimpleDataSource)))

(def options {:builder-fn rs/as-unqualified-lower-maps})

(defn required [name]
  (let [value (System/getenv name)]
    (when (or (nil? value) (empty? value))
      (throw (ex-info (str "Missing " name) {})))
    value))

(defn pool [user password size name]
  ;; A real driver DataSource keeps passwords out of JDBC URLs and pool logs.
  (let [source (doto (PGSimpleDataSource.)
                 (.setServerNames (into-array String [(required "PGHOST")]))
                 (.setPortNumbers (int-array [(Integer/parseInt (required "PGPORT"))]))
                 (.setDatabaseName (required "PGDATABASE"))
                 (.setUser user)
                 (.setPassword password)
                 (.setSslMode "verify-full")
                 (.setSslRootCert (required "PGSSLROOTCERT"))
                 (.setConnectTimeout 5)
                 (.setSocketTimeout 15)
                 (.setApplicationName name))
        config (doto (HikariConfig.)
                 (.setDataSource source)
                 (.setPoolName name)
                 (.setMaximumPoolSize size)
                 (.setMinimumIdle 0)
                 (.setConnectionTimeout 3000)
                 (.setValidationTimeout 2000)
                 (.setInitializationFailTimeout -1))]
    (HikariDataSource. config)))

(defn customer [source id]
  (jdbc/execute-one! source
    ["SELECT id,name,note,health,revision,updated_at FROM notebook.customers WHERE id=?" id]
    options))

(defn customers [source]
  (jdbc/execute! source
    ["SELECT id,name,health,revision FROM notebook.customers ORDER BY id LIMIT 20"] options))

(defn history [source id]
  (jdbc/execute! source
    ["SELECT revision,note,health,edited_at FROM notebook.customer_edits
       WHERE customer_id=? ORDER BY revision DESC LIMIT 20" id] options))

(defn save! [source id {:keys [note health revision]}]
  (jdbc/with-transaction [tx source]
    (if-let [updated
              (jdbc/execute-one! tx
                ["UPDATE notebook.customers
                    SET note=?,health=?,revision=revision+1,updated_at=clock_timestamp()
                  WHERE id=? AND revision=? AND revision<999999999999999999
                  RETURNING id,name,note,health,revision,updated_at"
                 note health id revision] options)]
      (do
        ;; Use tx here: using source would open a different connection/transaction.
        (jdbc/execute-one! tx
          ["INSERT INTO notebook.customer_edits(customer_id,revision,note,health,edited_at)
            VALUES (?,?,?,?,?)"
           id (:revision updated) (:note updated) (:health updated) (:updated_at updated)])
        updated)
      (throw (ex-info "The profile changed; reload before saving again." {:status 409})))))

(def activity-sql
  "SELECT activity_day::text AS day,count(*) AS events
     FROM notebook_fdw.activity
    WHERE customer_id=? AND activity_day>=? AND activity_day<=?
    GROUP BY activity_day ORDER BY activity_day LIMIT 31")

(defn activity [source id {:keys [from to]}]
  (let [rows (jdbc/execute! source
               [activity-sql id from to] options)
        counts (into {} (map (juxt :day :events)) rows)]
    ;; SQL dates are projected as text to avoid process-timezone conversion.
    (mapv (fn [day] {:day (str day) :events (get counts (str day) 0)})
          (take-while #(not (.isAfter % to)) (iterate #(.plusDays % 1) from)))))
