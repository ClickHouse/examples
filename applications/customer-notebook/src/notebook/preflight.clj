(ns notebook.preflight
  "Load the complete stable dependency graph without database credentials."
  (:require [hiccup2.core :as h]
            [next.jdbc :as jdbc]
            [reitit.ring :as ring]
            [ring.adapter.jetty]
            [ring.middleware.defaults])
  (:import (com.zaxxer.hikari HikariConfig HikariDataSource)
           (org.postgresql Driver)))

(defn -main [& _]
  (let [handler (ring/ring-handler
                  (ring/router [["/health" {:get (fn [_] {:status 200 :body "ok"})}]]))
        config (HikariConfig.)]
    (assert (= 200 (:status (handler {:request-method :get :uri "/health"}))))
    (assert (= "<p>&lt;synthetic&gt;</p>" (str (h/html [:p "<synthetic>"]))))
    (.setMaximumPoolSize config 2)
    (assert (= 2 (.getMaximumPoolSize config)))
    (assert (.acceptsURL (Driver.) "jdbc:postgresql://example.invalid/notebook"))
    (println "Stable Clojure/Ring/Reitit/Hiccup/next.jdbc/pgJDBC/Hikari graph loaded without a database.")
    (println "Clojure" (clojure-version) "Java" (System/getProperty "java.version"))))
