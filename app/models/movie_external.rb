class MovieExternal
  class Freebase < Externals::Freebase
    def setup
      @objclass = "movie"
      @search_type = "topic"
      @query_string = @obj.is_episode ? @obj.main.imdb.imdbid : @obj.imdb.imdbid
    end

    def netflixid
      cached_id = Rails.rcache.get("#{cache_prefix}:netflix:id")
      return (cached_id == "" ? nil : cached_id) if cached_id
      return nil if !topic
      netflix = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/netflix\/movie\/(.*)$/] }.first
      id = netflix ? netflix.value[/\/authority\/netflix\/movie\/(.*)/,1] : nil
      Rails.rcache.set("#{cache_prefix}:netflix:id", id, 1.week)
      id
    end

    def thetvdbid
      cached_id = Rails.rcache.get("#{cache_prefix}:thetvdb:id")
      return (cached_id == "" ? nil : cached_id) if cached_id
      return nil if !topic
      thetvdb = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/thetvdb\/series\/(.*)$/] }.first
      id = thetvdb ? thetvdb.value[/\/authority\/thetvdb\/series\/(.*)/,1] : nil
      Rails.rcache.set("#{cache_prefix}:thetvdb:id", id, 1.week)
      id
    end
  end

  class IMDb < Externals::IMDb
    IMDB_BASE="http://www.imdb.com/title/"
    MC_PAGE="/trivia?tab=mc"

    def setup
      @objclass = "movie"
      @is_short = (!@obj.genres.blank? && @obj.genres.map(&:genre).include?("Short"))
      @ttype = ""
      if @obj.is_episode
        @ttype = "ep"
      elsif @obj.title_category == "VG"
        @ttype = "vg"
      elsif @obj.title_category == "TV" || @obj.title_category == "TVS"
        @ttype = "tv"
      elsif !@is_short
        @ttype = "ft"
      end
    end

    def fetch_id
      @obj.imdb_id
    end

    def store_id(new_id)
      @obj.update_attribute(:imdb_id, new_id)
    end

    def search
      query = URI.encode_www_form_component("#{@obj.imdb_search_text}")
      urlparams = "ttype=#{@ttype}&s=tt&ref_=fn_tt_ex&q=#{query}"
      imdbdata = nil
      open(BASEURL+urlparams) do |u|
        imdbdata = u.read
      end
      return nil if !imdbdata
      doc = Nokogiri::HTML(imdbdata)
      result_list = doc.search(".findList .findResult")

      if result_list == 1
        tmp_imdbid = result_list.map do |item|
          item.search(".result_text a").attr('href').value[/^\/title\/(tt[^\/]+)/,1]
        end.first
        store_id(tmp_imdbid)
        return tmp_imdbid
      end
      return nil if result_list.blank?

      result_list = result_list.select { |x| is_matching?(x) }
      if result_list.size == 1
        tmp_imdbid = result_list.map do |item|
          item.search(".result_text a").attr('href').value[/^\/title\/(tt[^\/]+)/,1]
        end.first
        store_id(tmp_imdbid)
        return tmp_imdbid
      end
      return nil if result_list.blank?

      result_list = result_list.select { |x| is_matching_with_parent?(x) }
      if result_list.size == 1
        tmp_imdbid = result_list.map do |item|
          item.search(".result_text a").attr('href').value[/^\/title\/(tt[^\/]+)/,1]
        end.first
        store_id(tmp_imdbid)
        return tmp_imdbid
      end
      nil
    end

    def is_matching_with_parent?(imdb_entry)
      return false if !@obj.is_episode
      return false if !@obj.parent_id

      entry = imdb_entry.search(".result_text small").first.text.trim
      entry == "- #{@obj.main.imdb.imdb_like_title}"
    end

    def is_matching?(imdb_entry)
      entry = imdb_entry.search(".result_text").first
      if @obj.is_episode
        new_doc = Nokogiri::HTML(entry.to_html.split(/<br>/).first+"</td>")
        entry = new_doc.text.trim
      else
        entry = entry.text.trim
      end
      entry == imdb_like_title
    end

    def imdb_like_title
      title = nil
      year = nil
      if @obj.is_episode
        if @obj.episode_name
          title = @obj.episode_name
        else
          title = "#(#{@obj.episode_season}.#{@obj.episode_episode})"
        end
        year = "(#{@obj.full_year})" if !@obj.full_year.blank?
      else
        title = @obj.title
        title.gsub!(/^\"(.*)\"$/,'\1') if @obj.is_tvseries?
        year = "(#{@obj.title_year_uncounted})"
      end
        year_count = @obj.title_year_count ? "(#{@obj.title_year_count})" : nil
      title_type = nil
      if @obj.is_episode
        title_type = "(TV Episode)"
      elsif @obj.is_tvseries?
        title_type = "(TV Series)"
      elsif @is_short && @ttype == "tv"
        title_type = "(TV Short)"
      elsif @ttype == "tv"
        title_type = "(TV Movie)"
      elsif @is_short
        title_type = "(Short)"
      elsif @ttype == "vg"
        title_type = "(Video Game)"
      end
      [title, year_count, year, title_type].compact.join(" ")
    end

    def movie_connection_data
      return nil if @obj.movie_connections.count == 0
      page = movie_connection_page
      return nil if !page
      doc = Nokogiri::HTML(page)
      content = doc.search("#connections_content .list")
      groups = content.search("a[@name]")
      grouped_data = {}
      groups.each do |group|
        group_name = group.attr("name").gsub(/_/," ")
        grouped_data[group_name] = []
        current_sibling = group.next_sibling
        while(!((current_sibling.node_name == "a") && current_sibling.attr("name")))
          if(current_sibling.node_name == "div" &&
              current_sibling.attr("class")[/^soda (odd|even)/])
            item_link = current_sibling.search("a[@href]")
            item_imdbid = item_link.first.attr("href").gsub(/\/title\/(.*)\//, '\1')
            item_text = ""
            if current_sibling.search("br").first
              item_text = current_sibling.search("br").first.next_sibling.text
            end
            if item_link && item_link.first && item_link.first.next_sibling
              item_title = item_link.text + " " + item_link.first.next_sibling.text.gsub(/\u00a0/,""
).trim
              grouped_data[group_name] << {
                :title => item_title.to_s,
                :imdbid => item_imdbid.to_s,
                :text => item_text.to_s.trim
              }
            end
          end
          current_sibling = current_sibling.next_sibling
          break if !current_sibling
        end
      end

      grouped_data
    end

    def movie_connection_page
      cached_page = Rails.rcache.get("#{cache_prefix}:movie_connections:page")
      return cached_page if cached_page
      return nil if !movie_connection_url
      open(movie_connection_url) do |u|
        page_data = u.read
        Rails.rcache.set("#{cache_prefix}:movie_connections:page", page_data, 1.week)
        return page_data
      end
    end

    def movie_connection_url
      return nil if !imdbid
      IMDB_BASE+imdbid+MC_PAGE
    end
  end

  class Bing < Externals::Bing
    def setup
      @objclass = "movie"
      @extra_query = ""
      @section = "title"
      @id_prefix = "tt"
    end

    def fetch_id
      @obj.imdb_id
    end

    def store_id(new_id)
      @obj.update_attribute(:imdb_id, new_id)
    end
  end

  class Wikipedia < Externals::Wikipedia
    CATEGORIES={
      "TVS" => :television,
      "V" => :film,
      "TV" => :film,
      "M" => :film,
      "VG" => :videogame
    }
    TYPES={
      film: {
        type: "film",
        title: "name",
        image: "image"
      },
      television: {
        type: "television",
        title: "show_name",
        image: "image"
      }
    }

    def title
      type = TYPES[CATEGORIES[@movie.category_code]]
      box = infobox.first
      return nil if !box
      @title ||= box[type[:title]]
    end
  end

  class TMDb < Externals::TMDb
    def setup
      @objclass = "movie"
      @query_id = @obj.imdb.imdbid
      if @obj.is_episode && @obj.main
        @query_id_second = @obj.main.imdb.imdbid
        @has_secondary = true
      end
    end

    def results_blank?(results)
      results["movie_results"].blank? && results["tv_results"].blank?
    end

    def extract_results(results)
      unless results["movie_results"].blank?
        results["movie_results"].first["type"] = "movie"
        return results["movie_results"].first
      end
      unless results["tv_results"].blank?
        results["tv_results"].first["type"] = "tv"
        return results["tv_results"].first
      end
      nil
    end

    def images(cache_only = false)
      return nil if !info
      json_images = Rails.rcache.get("#{cache_prefix}:images")
      return JSON.parse(json_images) if json_images
      return nil if cache_only
      imgs = get(info["id"], info["type"], "images")
      imgs["backdrops"].each_with_index do |img,i|
        imgs["backdrops"][i].merge!(image_urls(img, "backdrop"))
      end
      imgs["posters"].each_with_index do |img,i|
        imgs["posters"][i].merge!(image_urls(img, "poster"))
      end
      return nil if imgs["backdrops"].blank? && imgs["posters"].blank?
      Rails.rcache.set("#{cache_prefix}:images", imgs.to_json, 1.week)
      imgs
    end
  end
end
