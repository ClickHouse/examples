(ns notebook.http
  (:require [notebook.db :as db]
            [notebook.inputs :as input]
            [notebook.views :as views]
            [reitit.ring :as ring]
            [ring.middleware.defaults :as defaults])
  (:import (java.io ByteArrayInputStream ByteArrayOutputStream InputStream)
           (java.nio ByteBuffer)
           (java.nio.charset StandardCharsets CodingErrorAction)
           (java.sql SQLException)))

(defn html [status body]
  {:status status
   :headers {"Content-Type" "text/html; charset=utf-8"
             "Cache-Control" "no-store"
             "Content-Security-Policy" "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"}
   :body body})

(defn validate-form-encoding! [body]
  ;; Ring's URL decoder can replace malformed UTF-8. Reject it before decoding.
  (let [encoded (String. ^bytes body StandardCharsets/ISO_8859_1)
        decoded (ByteArrayOutputStream.)]
    (loop [index 0]
      (when (< index (.length encoded))
        (let [ch (.charAt encoded index)]
          (if (= ch \%)
            (do
              (when (> (+ index 3) (.length encoded)) (input/invalid))
              (let [hex (.substring encoded (inc index) (+ index 3))]
                (when-not (re-matches #"[0-9a-fA-F]{2}" hex) (input/invalid))
                (.write decoded (Integer/parseInt hex 16)))
              (recur (+ index 3)))
            (do (.write decoded (int ch)) (recur (inc index)))))))
    (try
      (-> (StandardCharsets/UTF_8)
          (.newDecoder)
          (.onMalformedInput CodingErrorAction/REPORT)
          (.onUnmappableCharacter CodingErrorAction/REPORT)
          (.decode (ByteBuffer/wrap (.toByteArray decoded))))
      (catch java.nio.charset.CharacterCodingException _ (input/invalid)))))

(defn wrap-body-limit [handler]
  (fn [request]
    (if (= :post (:request-method request))
      (let [body (.readNBytes ^InputStream (:body request) 4097)]
        (when (> (alength body) 4096)
          (throw (ex-info "Body too large" {:status 413})))
        (when-not (re-matches #"(?i)application/x-www-form-urlencoded(?:;.*)?"
                             (get-in request [:headers "content-type"] ""))
          (input/invalid))
        (validate-form-encoding! body)
        (handler (assoc request :body (ByteArrayInputStream. body))))
      (handler request))))

(defn wrap-errors [handler]
  (fn [request]
    (try (handler request)
      (catch clojure.lang.ExceptionInfo error
        (html (or (:status (ex-data error)) 500)
              (views/error (case (:status (ex-data error))
                             400 "Invalid fields or request encoding."
                             413 "Form body exceeds 4 KiB."
                             404 "Customer not found."
                             "Request unavailable."))))
      (catch SQLException error
        ;; SQLState is useful evidence; SQL messages may contain private values.
        (binding [*out* *err*] (println "Database request failed; SQLState" (.getSQLState error)))
        (html 503 (views/error "Database request unavailable. Your note was not confirmed; reload to check its current revision."))))))

(defn existing [operational id]
  (or (db/customer operational id) (throw (ex-info "Missing customer" {:status 404}))))

(defn handler [operational reporting]
  (let [profile-response
        (fn [id submitted conflict?]
          (html (if conflict? 409 200)
                (views/profile (existing operational id) (db/history operational id)
                               submitted conflict?)))
        routes
        (ring/ring-handler
          (ring/router
            [["/" {:get (fn [_] (html 200 (views/index (db/customers operational))))}]
             ["/health" {:get (fn [_] {:status 200 :body "ok"})}]
             ["/customers/:id"
              {:get (fn [request]
                      (profile-response (input/uuid (get-in request [:path-params :id])) nil false))
               :post (fn [request]
                       (let [id (input/uuid (get-in request [:path-params :id]))
                             submitted (input/edit (:form-params request))]
                         (existing operational id)
                         (try
                           (db/save! operational id submitted)
                           {:status 303 :headers {"Location" (str "/customers/" id)} :body ""}
                           (catch clojure.lang.ExceptionInfo error
                             (if (= 409 (:status (ex-data error)))
                               (profile-response id submitted true)
                               (throw error))))))}]
             ["/customers/:id/activity"
              {:get (fn [request]
                      (let [id (input/uuid (get-in request [:path-params :id]))
                            range (input/date-range (:query-params request))]
                        (existing operational id)
                        (try (html 200 (views/report id (db/activity reporting id range)))
                          (catch SQLException error
                            (binding [*out* *err*]
                              (println "Analytical request failed; SQLState" (.getSQLState error)))
                            (html 503 (views/error "Activity is temporarily unavailable. Operational notes can still be saved."))))))}]] )
          (ring/create-default-handler
            {:not-found (constantly (html 404 (views/error "Page not found.")))}))]
    (-> routes
        (defaults/wrap-defaults
          (-> defaults/site-defaults
              (assoc-in [:session :cookie-attrs :same-site] :strict)
              (assoc-in [:security :anti-forgery]
                {:error-response (html 403 (views/error "Session check failed. Reload the form before saving."))})))
        wrap-body-limit
        wrap-errors)))
