# encoding: utf-8

Keks::Application.routes.draw do
  resources :password_resets

  match "dot/:sha256.png", to: "dot#simple", :as => "render_dot", :via => :get
  match "preview", to: "latex#complex", :as => "render_preview", :via => :post



  root :to => "main#overview"

  get "main/overview"
  match "hitme", as: "main_hitme", to: "main#hitme"
  match "help", as: "main_help", to: "main#help"


  resources :users, except: :index
  match "users/:id/enrollment" => "users#enroll", as: "enroll_user", via: :post
  match "users/:id/starred" => "users#starred", as: "starred", via: :get
  match "users/:id/history" => "users#history", as: "history", via: :get
  match "questions/:id/star" => "questions#star", as: "star_question", via: :get
  match "questions/:id/unstar" => "questions#unstar", as: "unstar_question", via: :get
  match "questions/:id/perma" => "questions#perma", as: "perma_question", via: :get
  match "stats/:question_id" => "stats#new", as: "new_stat", via: :post


  get "admin/overview"
  scope "/admin" do
    resources :text_storage, only: :update

    match "users", to: "users#index", as: "user_index", via: :get
    match "users/:id/reviews", to: "users#reviews", as: "user_reviews", via: :get
    match "toggle_reviewer/:id", to: "users#toggle_reviewer", as: "user_toggle_reviewer", via: :put
    match "toggle_admin/:id", to: "users#toggle_admin", as: "user_toggle_admin", via: :put

    match "reviews", to: "reviews#messages", as: "reviews", via: :get


    match "reviews/need_attention", to: "reviews#need_attention", as: "need_attention_questions", via: :get

    match "reviews/filter/:filter", to: "reviews#filter", as: "review_filter",via: :get
    match "reviews/find_next/:filter/", to: "reviews#find_next", as: "review_find_next",via: :get
    match "reviews/find_next/:filter/:next", to: "reviews#find_next", as: "review_find_next",via: :get

    resources :questions do
      resources :answers
      resources :hints
      match "toggle_release", to: "questions#toggle_release", as: "toggle_release", via: :put
      match "overwrite_reviews", to: "questions#overwrite_reviews", as: "overwrite_reviews", via: :put
      match "review", to: "reviews#review", as: "review", via: :get
      match "review", to: "reviews#save", as: "review_save", via: :post # new reviews
      match "copy", to: "questions#copy", as: "copy", via: :get
      match "copy_to", to: "questions#copy_to", as: "copy_to", via: :post
      get "list_cat/:category_id", to: "questions#list_cat", on: :collection, as: "list_cat"
      get "select", to: "questions#select", on: :collection, as: "select"
      get :search, on: :collection
    end

    match "single_parent_select", to: "questions#single_parent_select", as: "single_parent_select", via: :get

    resources :categories do
      get "index_details/:category_ids", to: "categories#index_details", on: :collection, as: "index_details"
    end
    match "categories/:id/release", to: "categories#release", :as => "release_category", via: :get
    match "categories/:group_title/activate", to: "categories#activate", :as => "activate_category", via: :get
    match "categories/:group_title/deactivate", to: "categories#deactivate", :as => "deactivate_category", via: :get
    match "suspicious_assocations", to: "categories#suspicious_associations", :as => "suspicious_associations", via: :get
    match "category_report", to: "stats#category_report", :as => "stat_category_report", via: :get
    match "activity_report", to: "stats#activity_report", :as => "stat_activity_report", via: :get
    match "report/:enrollment_key", to: "stats#report", :as => "stat_report", via: :get

    match "tree", to: "admin#tree", :as => "tree", via: :get
    #~ match "tree", to: "admin#tree", :as => "tree", via: :get
    match "export", to: "admin#export", :as => "export", via: :get
    match "export_question/:question_id", to: "admin#export_question", :as => "export_question", via: :get
  end

  #~ match "category/:id/questions", to: "categories#questions", :as => "category_question", via: :get
  match "main/questions", to: "main#questions", :as => "main_question", via: :get
  match "main/single_question", to: "main#single_question", :as => "main_single_question", via: :get
  match "main/multiple_question", to: "main#multiple_question", :as => "main_multiple_question", via: :get
  match "feedback", to: "main#feedback", :as => "feedback", via: :get
  match "feedback_send", to: "main#feedback_send", :as => "feedback_send", via: :post
  match "random_xkcd", to: "main#random_xkcd", :as => "random_xkcd", via: :get
  match "specific_xkcd/:id", to: "main#specific_xkcd", :as => "specific_xkcd", via: :get

  resources :sessions, only: [:new, :create, :destroy]


  match '/signup', to: 'users#new'
  match '/signin', to: 'sessions#new'
  match '/signout', to: 'sessions#destroy'


  match '/perf', to: 'perfs#create', via: :post

  # api
  namespace :api do
    namespace :v1 do
      resources :questions, only: [:show]
    end
  end

  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
