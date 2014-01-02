module Externals
  class TMDb
    TMDB_API_URL="http://api.themoviedb.org/3"
    TMDB_CFG_URL=TMDB_API_URL+"/configuration?api_key="+TMDB_API_KEY
    IMAGE_SIZES = {
      "backdrop" => {
        thumb: 0,
        medium: 1,
        large: 2
      },
      "poster" => {
        thumb: 1,
        medium: 3,
        large: 4
      },
      "profile" => {
        thumb: 0,
        medium: 1,
        large: 2
      },
    }

    def initialize(obj)
      @obj = obj
      @config = config
      setup
    end

    def config
      json_data = Rails.rcache.get("tmdb:config")
      return JSON.parse(json_data) if json_data
      begin
        open(TMDB_CFG_URL) do |file|
          json_data = file.read
          Rails.rcache.set("tmdb:config", json_data, 1.week)
          return JSON.parse(json_data)
        end
      rescue
      end
    end

    def find(do_secondary = false)
      result = nil
      imdbid = do_secondary ? @query_id_second : @query_id
      if !imdbid && !do_secondary && @has_secondary
        imdbid = @query_id_second
      end
      return nil if !imdbid
      open(TMDB_API_URL+"/find/#{imdbid}?external_source=imdb_id&api_key="+TMDB_API_KEY) do |u|
        result = JSON.parse(u.read)
      end
      if @has_secondary && results_blank?(result) && !do_secondary
        return find(true)
      end
      if results_blank?(result)
        return nil
      end
      extract_results(result)
    end

    def info(cache_only = false)
      json_data = Rails.rcache.get("#{cache_prefix}:info")
      return JSON.parse(json_data) if json_data
      return nil if cache_only
      results = find
      return nil if !results
      info = get(results["id"], results["type"])
      info["type"] = results["type"]
      Rails.rcache.set("#{cache_prefix}:info", info.to_json, 1.week)
      info
    end

    def get(tmdb_id, type, section = nil)
      section = section ? "/#{section}" : ""
      open(TMDB_API_URL+"/#{type}/#{tmdb_id}#{section}?api_key="+TMDB_API_KEY) do |u|
        return JSON.parse(u.read)
      end
    end

    def image_urls(img, type)
      base = @config["images"]["base_url"]
      thumb = @config["images"]["#{type}_sizes"][IMAGE_SIZES[type][:thumb]]
      medium = @config["images"]["#{type}_sizes"][IMAGE_SIZES[type][:medium]]
      large = @config["images"]["#{type}_sizes"][IMAGE_SIZES[type][:large]]
      {
        "image_url_thumb" => base+thumb+img["file_path"],
        "image_url_medium" => base+medium+img["file_path"],
        "image_url_large" => base+large+img["file_path"],
        "image_url" => base+"original"+img["file_path"]
      }
    end

    def cache_prefix
      "#{@objclass}:#{@obj.id}:externals:tmdb"
    end
  end
end
