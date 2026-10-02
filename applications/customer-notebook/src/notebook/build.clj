(ns notebook.build
  (:require [clojure.java.io :as io]))

(defn -main [& _]
  (.mkdirs (io/file "target/classes"))
  (binding [*compile-path* "target/classes"]
    (doseq [namespace '[notebook.inputs notebook.db notebook.views notebook.http notebook.main notebook.security]]
      (compile namespace)))
  (println "Application namespaces compiled without database credentials."))
