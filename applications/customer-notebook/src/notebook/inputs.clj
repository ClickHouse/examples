(ns notebook.inputs
  (:import (java.time LocalDate)
           (java.time.temporal ChronoUnit)
           (java.util UUID)))

(defn invalid []
  (throw (ex-info "Invalid input" {:status 400})))

(defn safe-text? [value]
  (and (string? value)
       (loop [index 0]
         (if (= index (.length ^String value))
           true
           (let [ch (.charAt ^String value index)]
             (cond
               (Character/isHighSurrogate ch)
               (and (< (inc index) (.length ^String value))
                    (Character/isLowSurrogate (.charAt ^String value (inc index)))
                    (recur (+ index 2)))
               (Character/isLowSurrogate ch) false
               (and (Character/isISOControl ch) (not (#{\newline \return \tab} ch))) false
               :else (recur (inc index))))))))

(defn uuid [value]
  (when-not (and (string? value)
                 (re-matches #"(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" value))
    (invalid))
  (UUID/fromString value))

(defn revision [value]
  ;; Bound the decimal representation before conversion, even for malicious forms.
  (when-not (and (string? value) (<= 1 (count value) 18)
                 (re-matches #"[0-9]+" value))
    (invalid))
  (Long/parseLong value))

(defn edit [params]
  (when-not (every? #{"note" "health" "revision" "__anti-forgery-token"} (keys params))
    (invalid))
  (let [note (get params "note")
        health (get params "health")]
    (when-not (and (safe-text? note) (<= (count note) 2000)
                   (#{"healthy" "watch" "risk"} health))
      (invalid))
    {:note note :health health :revision (revision (get params "revision"))}))

(defn date-range [params]
  (when-not (every? #{"from" "to"} (keys params)) (invalid))
  (let [parse-date (fn [value]
                     (when-not (and (string? value)
                                    (re-matches #"[0-9]{4}-[0-9]{2}-[0-9]{2}" value)) (invalid))
                     (try (LocalDate/parse value) (catch Exception _ (invalid))))
        from (parse-date (get params "from"))
        to (parse-date (get params "to"))
        length (inc (.between ChronoUnit/DAYS from to))]
    (when-not (and (<= 1 length 31)
                   (not (.isBefore from (LocalDate/parse "2000-01-01")))
                   (not (.isAfter to (LocalDate/parse "2100-12-31"))))
      (invalid))
    {:from from :to to :length length}))
