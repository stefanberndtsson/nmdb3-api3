module Externals
  class Bing
    require 'open-uri'
    BASEURL="http://www.bing.com/search?go=&qs=n&form=QBLH&filt=all&sc=0-14&sp=-1&sk=&format=rss&q="

    def initialize(obj)
      @obj = obj
      setup
    end

    def search_rss(cookies = nil)
      query_string = @obj.imdb_search_text
      query = URI.encode_www_form_component("#{query_string} #{@extra_query} site:www.imdb.com/#{@section}")
      headers = { }
      if !cookies && Rails.rcache.get("#{cache_prefix}:bing:cookies")
        cookies = Rails.rcache.get("#{cache_prefix}:bing:cookies")
      end
      headers["Cookie"] = cookies if cookies
      open(BASEURL+query, headers) do |u|
        rssdata = u.read
        if !cookies && rssdata[/sj_cook.set\("_FP", "BDCE", "([^"]+)", .*sj_cook.set\("_FP", "BDCEH", "([^"]+)", /]
          cookies = ["_FP=BDCE="+$1, "BDCEH="+$2].join("&")
          expire = (Time.now+2.years).strftime("%a, %d-%b-%Y %H:%M:%S GMT")
          recvd_cookies = u.meta['set-cookie'].split(/path=\/, /).map { |x| x.split(/;/).first }
          recvd_cookies << cookies
          cookies = recvd_cookies.join("; ")
          Rails.rcache.set("#{cache_prefix}:bing:cookies", cookies, 1.week)
          return search_rss(recvd_cookies.join("; "))
        end
        doc = Nokogiri::XML(rssdata)
        results = {}
        results["items"] = []
        doc.search("/rss/channel/item").each do |item|
          link = item.search("link").text
          title = item.search("title").text
          results["items"] << {
            "title" => title,
            "link" => link
          } if results["items"].size < 5
        end
        return results
      end
    end

    def imdbid
      tmp_imdbid = fetch_id
      if !tmp_imdbid
        return nil if Rails.rcache.get("#{cache_prefix}:failed_scan")
        results = search_rss
        find_one = results["items"].select do |item|
          tmp = item["link"][/^http:\/\/www.imdb.com\/#{@section}\/(#{@id_prefix}\d+)\/$/]
          next false if !tmp
          tmp
        end.map {|x| x["link"]}.uniq

        if find_one.size == 1
          tmp_imdbid = find_one.first[/^http:\/\/www.imdb.com\/#{@section}\/(#{@id_prefix}\d+)\/$/,1]
        else
          find_same = results["items"].map do |item|
            tmp = item["link"][/^http:\/\/www.imdb.com\/#{@section}\/(#{@id_prefix}\d+)\/.*$/,1]
            next false if !tmp
            tmp
          end.uniq
          if find_same.size == 1
            tmp_imdbid = find_same.first
          else
            Rails.rcache.set("#{cache_prefix}:failed_scan", true, 1.week)
            return nil
          end
        end

        store_id(tmp_imdbid)
      end
      tmp_imdbid
    end

    def cache_prefix
      # Bing is only used for IMDb-ID lookup, hence imdb here and not bing
      "#{@objclass}:#{@obj.id}:externals:imdb"
    end
  end
end
