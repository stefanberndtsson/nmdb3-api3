module Externals
  class Freebase
    def initialize(obj)
      @obj = obj
      setup
      FreebaseAPI.session = FreebaseAPI::Session.new(key: GOOGLE_API_KEY)
    end

    def search
      topic_id = Rails.rcache.get("#{cache_prefix}:topic:id")
      return topic_id if topic_id
      return nil if !@query_string
      res = FreebaseAPI::Topic.search(@query_string, filter: "(all type:#{@search_type})")
      @query ||= res.first ? res.first.last.id : nil
      Rails.rcache.set("#{cache_prefix}:topic:id", @query, 1.week) if @query
      @query
    end

    def topic
      return nil if !@query_string
      search_result = search
      return nil if !search_result
      @topic ||= FreebaseAPI::Topic.get(search_result)
    end

    def wikipedia_pages
      titles = {}
      cached_page_count = Rails.rcache.get("#{cache_prefix}:wikipedia_page_count")
      if cached_page_count
        cached_page_count.to_i.times do |i|
          lang = Rails.rcache.get("#{cache_prefix}:wikipedia_page:#{i}:lang")
          title = Rails.rcache.get("#{cache_prefix}:wikipedia_page:#{i}:title")
          titles[lang] = title
        end
      else
        return nil if !topic
        topic.property('/type/object/key')
          .select { |x| x.value[/^\/wikipedia\/([^\/]+)_title\//] }
          .sort_by {|x| x.value}
          .each_with_index do |obj,i|
          if obj.value[/^\/wikipedia\/([^\/]+)_title\/(.*)/]
            lang = $1
            title = decode_string($2)
            titles[lang] = title
            Rails.rcache.set("#{cache_prefix}:wikipedia_page:#{i}:lang", lang, 1.week)
            Rails.rcache.set("#{cache_prefix}:wikipedia_page:#{i}:title", title, 1.week)
            Rails.rcache.set("#{cache_prefix}:wikipedia_page_count",
                         Rails.rcache.get("#{cache_prefix}:wikipedia_page_count").to_i+1,
                         1.week)
          end
        end
      end
      titles
    end

    def twitter_name
      cached_twitter_name = Rails.rcache.get("#{cache_prefix}:twitter:name")
      return cached_twitter_name if cached_twitter_name
      return nil if !topic
      twitter_entry = topic.property('/type/object/key').select { |x| x.value[/^\/authority\/twitter\/(.*)/] }.first

      if !twitter_entry
        Rails.rcache.set("#{cache_prefix}:twitter:name", nil, 1.week)
        return nil
      end

      twitter_name = twitter_entry.value[/^\/authority\/twitter\/(.*)/,1]
      Rails.rcache.set("#{cache_prefix}:twitter:name", twitter_name, 1.week)
      twitter_name
    end

    def decode_string(str)
      str.gsub(/\$([0-9A-F]{4})/) { [$1.hex].pack("U") }
    end

    def cache_prefix
      "#{@objclass}:#{@obj.id}:externals:freebase"
    end
  end
end
