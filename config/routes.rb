Nmdb3Api3::Application.routes.draw do
  resources :searches do
    collection do
      get 'movies'
      get 'people'
      get 'solr_movies'
      get 'solr_people'
      get 'solr_suggest_movies'
      get 'solr_suggest_people'
    end
  end

  resources :keywords

  resources :genres

  resources :people do
    member do
      get 'as_role'
      get 'biography'
      get 'trivia'
      get 'quotes'
      get 'other_works'
      get 'publicity'
      get 'info'
      get 'externals'
      get 'cover'
      get 'top_movies'
      get 'images'
      get 'by_genre'
      get 'by_keyword'
    end
  end

  resources :movies do
    member do
      get 'genres'
      get 'languages'
      get 'keywords'
      get 'cast_members'
      get 'plots'
      get 'trivia'
      get 'goofs'
      get 'quotes'
      get 'externals'
      get 'cover'
      get 'images'
      get 'episodes'
      get 'local_connections'
      get 'connections'
      get 'additionals'
      get 'similar'
      get 'new_title'
      get 'versions'
      get 'soundtrack'
      get 'taglines'
      get 'technicals'
    end
    collection do
      get 'new_title'
    end
  end

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
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

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
