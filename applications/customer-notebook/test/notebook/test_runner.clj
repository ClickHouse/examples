(ns notebook.test-runner
  (:require [clojure.test :as test]
            [notebook.inputs-test]))

(defn -main [& _]
  (let [results (test/run-tests 'notebook.inputs-test)]
    (shutdown-agents)
    (when (pos? (+ (:fail results) (:error results))) (System/exit 1))))
