module Wikipedia
  class Page
    attr_reader :data
  end
end

module Externals
  class Wikipedia
    IMAGE_SIZE=640
    def initialize(movie, page_title, lang = "en")
      @movie = movie
      @page_title = page_title
      @lang = lang
    end

    def client
      @client ||= ::Wikipedia::Client.new
    end

    def domain
      @domain ||= @lang+".wikipedia.org"
    end

    def page
      @page ||= client.find(@page_title, domain: domain)
    end

    def content
      page.content.gsub(/<!-- .*? -->/m, '')
    end

    def infobox
      @infobox ||= content.scan(/(?=\{\{[Ii]nfobox((?:[^{}]++|\{\{\g<1>\}\})++)\}\})/).map do |box|
        box.map do |line|
          box_type = line.split(/[\n\|]+/).first.trim.downcase
          values = line.split(/\n*\s*\|\s*/).map do |item|
            item.scan(/^([^=]+?)\s*=\s*(.*)$/).first
          end
          hashed_values = nil
          if !values.blank? && !values.compact.blank?
            hashed_values = Hash[values.compact]
            hashed_values["box_type"] = box_type
          end
          hashed_values
        end.first
      end
    end

    def image
      box = infobox.first
      return nil if !box
      image = box["image"]
      if image.match(/^(\[\[|)(File|Image):([^\|]+)(|\|.*)(\]\]|)$/)
        image = $3
        image.gsub!(/\]\]$/,'')
        image.gsub!(/^\[\[/,'')
      end
      @image ||= image
    end

    def image_url
      return @image_url if @image_url
      if !image
        @image_url = nil
        return nil
      end

      image_pages = client.find_image("File:"+image, { iiurlwidth: IMAGE_SIZE })
      image_page_ids = image_pages.data["query"]["pages"].keys if image_pages
      if !image_pages || image_page_ids.size == 0
        @image_url = nil
        return nil
      end
      pgs = image_pages.data["query"]["pages"]
      pg_select = pgs.select do |pg|
        pgs[pg] && pgs[pg]["imageinfo"] &&
          (pgs[pg]["imageinfo"].first.keys.include?("thumburl") ||
          pgs[pg]["imageinfo"].first.keys.include?("url"))
      end
      if pg_select.blank?
        @image_url = nil
        return nil
      end

      image_page_id = pg_select.keys.first
      image_page = pg_select[image_page_id]["imageinfo"].first
      image_url = image_page["thumburl"] ? image_page["thumburl"] : image_page["url"]
      @image_url = image_url
    end
  end
end
