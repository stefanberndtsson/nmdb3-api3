module PersonExternal
  class Freebase < Externals::Freebase
    def setup
      @objclass = "person"
      @search_type = "person"
      @query_string = @obj.imdb.imdbid
    end
  end

  class IMDb < Externals::IMDb
    def setup
      @objclass = "person"
    end
  end

  class Bing < Externals::Bing
    def setup
      @objclass = "person"
      @extra_query = ""
      @section = "name"
      @id_prefix = "nm"
    end

    def fetch_id
      tmp = Rails.rcache.get("#{cache_prefix}:id")
      tmp.blank? ? nil : tmp
    end

    def store_id(new_id)
      return if !new_id
      Rails.rcache.set("#{cache_prefix}:id", new_id)
    end
  end

  class Wikipedia < Externals::Wikipedia
  end

  class TMDb < Externals::TMDb
    def setup
      @objclass = "person"
      @query_id = @obj.imdb.imdbid
    end

    def results_blank?(results)
      results["person_results"].blank?
    end

    def extract_results(results)
      unless results["person_results"].blank?
        results["person_results"].first["type"] = "person"
        return results["person_results"].first
      end
      nil
    end

    def images(cache_only = false)
      return nil if !info
      json_images = Rails.rcache.get("#{cache_prefix}:images")
      return JSON.parse(json_images) if json_images
      return nil if cache_only
      imgs = get(info["id"], info["type"], "images")
      imgs["profiles"].each_with_index do |img,i|
        imgs["profiles"][i].merge!(image_urls(img, "profile"))
      end
      return nil if imgs["profiles"].blank?
      Rails.rcache.set("#{cache_prefix}:images", imgs.to_json, 1.week)
      imgs
    end
  end
end
