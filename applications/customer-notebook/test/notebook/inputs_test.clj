(ns notebook.inputs-test
  (:require [clojure.test :refer [deftest is testing]]
            [notebook.inputs :as input]
            [notebook.http :as http]
            [notebook.views :as views])
  (:import (java.nio.charset StandardCharsets)))

(deftest bounded-edit-input
  (is (= {:note " Useful note " :health "watch" :revision 7}
         (input/edit {"note" " Useful note " "health" "watch" "revision" "7"})))
  (doseq [value ["" "-1" (apply str (repeat 10000 "9")) "18446744073709551615"]]
    (is (thrown? clojure.lang.ExceptionInfo (input/revision value))))
  (doseq [note [(str "\u0000" " x ") (str (char 0xD800)) (str (char 0xDC00))
                (apply str (repeat 2001 "a"))]]
    (is (thrown? clojure.lang.ExceptionInfo
                 (input/edit {"note" note "health" "healthy" "revision" "0"}))))
  (is (input/safe-text? "Line one\n\tLine two 😀"))
  (is (thrown? clojure.lang.ExceptionInfo
               (input/edit {"note" "ok" "health" "healthy" "revision" "0" "owner" "forged"}))))

(deftest strict-wire-encoding
  (doseq [body ["note=%ED%A0%80" "note=%ED%B0%80" "note=%FF" "note=%0" "note=%ZZ"]]
    (is (thrown? clojure.lang.ExceptionInfo
                 (http/validate-form-encoding! (.getBytes body StandardCharsets/UTF_8)))))
  (is (some? (http/validate-form-encoding! (.getBytes "note=%F0%9F%98%80" StandardCharsets/UTF_8)))))

(deftest bounded-utc-range
  (is (= 31 (:length (input/date-range {"from" "2026-09-01" "to" "2026-10-01"}))))
  (doseq [date ["2000-01-01" "2100-12-31"]]
    (is (= 1 (:length (input/date-range {"from" date "to" date})))))
  (doseq [params [{"from" "2026-09-01" "to" "2026-10-02"}
                  {"from" "2026-09-30" "to" "2026-09-29"}
                  {"from" "2026-02-30" "to" "2026-03-01"}
                  {"from" "1999-12-31" "to" "2000-01-01"}
                  {"from" "2100-12-31" "to" "2101-01-01"}]]
    (is (thrown? clojure.lang.ExceptionInfo (input/date-range params)))))

(deftest retained-stale-form-is-escaped
  (let [html (views/profile {:id (input/uuid "00000000-0000-0000-0000-000000000001")
                            :name "Synthetic" :note "Current" :health "healthy" :revision 8}
                           [] {:note "<script>alert(1)</script>" :health "risk" :revision 7} true)]
    (is (.contains html "&lt;script&gt;alert(1)&lt;/script&gt;"))
    (is (.contains html "value=\"7\""))
    (is (.contains html "Current revision 8"))
    (is (not (.contains html "<script>")))))
