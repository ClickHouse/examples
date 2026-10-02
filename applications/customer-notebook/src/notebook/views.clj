(ns notebook.views
  (:require [hiccup2.core :as h]
            [ring.middleware.anti-forgery :refer [*anti-forgery-token*]]))

(def style
  "body{font:17px system-ui;background:#f7f7f3;color:#18291f;max-width:780px;margin:40px auto;padding:0 20px}a{color:#245b42}textarea{width:100%;box-sizing:border-box;padding:12px;font:inherit}select,button,input{font:inherit;padding:8px;margin:5px 0}button{background:#245b42;color:white;border:0;border-radius:6px}section{background:white;padding:22px;margin:20px 0;border:1px solid #d9dfd7;border-radius:10px}.notice{background:#fff2cf;padding:14px}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:8px;border-bottom:1px solid #ddd}pre{white-space:pre-wrap;overflow-wrap:anywhere}")

(defn page [title content]
  (str "<!doctype html>"
       (h/html [:html {:lang "en"}
                 [:head [:meta {:charset "utf-8"}]
                  [:meta {:name "viewport" :content "width=device-width,initial-scale=1"}]
                  [:title title] [:style style]]
                 [:body [:a {:href "/"} "Customer notebook"]
                  [:p "Synthetic customers · trusted local operator workbench"] content]])))

(defn index [rows]
  (page "Customer notebook"
    [:section [:h1 "Customer notebook"]
     [:p "Keep a short operational note and a manual health label."]
     [:ul (for [row rows]
            [:li [:a {:href (str "/customers/" (:id row))} (:name row)]
             (str " · " (:health row) " · revision " (:revision row))])]]))

(defn profile [customer edits submitted conflict?]
  (let [values (or submitted customer)
        id (:id customer)]
    (page (:name customer)
      [:div
       [:section [:h1 (:name customer)]
        (when conflict?
          [:div.notice {:role "alert"}
           [:strong "This profile changed after you opened it."]
           [:p "Your submitted values and original revision are retained below. Reload the profile, review its current values, then decide what to save."]
           [:p (str "Current revision " (:revision customer) ", health " (:health customer))]
           [:pre (:note customer)]
           [:a {:href (str "/customers/" id)} "Reload current profile"]])
        [:form {:method "post" :action (str "/customers/" id)}
         [:input {:type "hidden" :name "__anti-forgery-token" :value *anti-forgery-token*}]
         [:input {:type "hidden" :name "revision" :value (str (:revision values))}]
         [:label {:for "note"} "Note (maximum 2,000 characters)"]
         [:textarea {:id "note" :name "note" :rows 6 :maxlength 2000} (:note values)]
         [:label {:for "health"} "Manual health"]
         [:select {:id "health" :name "health"}
          (for [value ["healthy" "watch" "risk"]]
            [:option {:value value :selected (= value (:health values))} value])]
         [:p (str "Editing revision " (:revision values))]
         [:button {:type "submit"} "Save note"]]]
       [:section [:h2 "Activity"]
        [:p "View sample daily activity. If reports are unavailable, you can still save notes."]
        [:form {:method "get" :action (str "/customers/" id "/activity")}
         [:label "From " [:input {:type "date" :name "from" :value "2026-09-28" :min "2000-01-01" :max "2100-12-31" :required true}]]
         [:label " To " [:input {:type "date" :name "to" :value "2026-09-30" :min "2000-01-01" :max "2100-12-31" :required true}]]
         [:button "View activity (up to 31 days)"]]]
       [:section [:h2 "Recent edits (20 maximum)"]
        (if (empty? edits) [:p "No edits yet."]
          [:ol (for [edit edits]
                 [:li [:p (str "Revision " (:revision edit) " · " (:health edit) " · " (:edited_at edit))]
                  [:pre (:note edit)]])])]])))

(defn report [id rows]
  (page "Customer activity"
    [:section [:h1 "Synthetic daily activity"]
     [:a {:href (str "/customers/" id)} "Return to profile"]
     [:table [:thead [:tr [:th "UTC day"] [:th "Events"]]]
      [:tbody (for [row rows]
                [:tr [:td (:day row)] [:td (str (:events row))]])]]]))

(defn error [message]
  (page "Request unavailable" [:section [:h1 "Request unavailable"] [:p message]]))
