require 'rubygems'
require 'nokogiri'
module ForumPost
  class Document
    DEFAULT_OPTIONS = {
      :min_length => 5,
      :min_text_length => 15
    }.freeze

    REGEXES = {
        :unlikelyCandidatesRe => /combx|community|disqus|extra|foot|header|menu|remark|rss|shoutbox|sidebar|sponsor|ad-break|agegate|pagination|pager|popup/i,
        :maybe_post => /article|body|column|main|content|post|topic|text|info|message|item|bord|forum/i,
        :not_post => /author|head|avatar|profile|rank|user|uid/i,
        :divToPElementsRe => /<(a|blockquote|dl|div|img|ol|p|pre|table|ul)/i,
        :replaceBrsRe => /(<br[^>]*>[ \n\r\t]*){2,}/i,
        :replaceFontsRe => /<(\/?)font[^>]*>/i
    }

    attr_accessor :options, :html

    def initialize(input, options = {})
      @input = input.gsub(REGEXES[:replaceBrsRe], '</p><p>').gsub(REGEXES[:replaceFontsRe], '<\1span>')
      @options = DEFAULT_OPTIONS.merge(options)
      make_html
    end

    def make_html
      @html = Nokogiri::HTML(@input, nil, 'UTF-8')
    end

    def content
      remove_script_and_style!#去除scrpt和style
      remove_unlikely_candidates!#去除不可能是发帖内容的标签
      transform_misused_divs_into_p!#把一些噪音的div转换成p标签
			better_post = likely_posts
			if better_post.size > 0
			  debug("post>4")
     		handle_html=most_likely_posts(better_post)
			else
				handle_html=@html
			  debug("post<4")
		  end	
	    bests=handle_html.css("div,tr,td") 
			if bests.size==0 
				debug("best_one:#{bests.name}.#{bests[:class]} #{bests[:id]}")
				return handle_html.text.gsub(/\s(\s+)/,"")	 
			else
				bests.map{|best| debug("bests:#{best.name}.#{best[:class]} #{best[:id]}")}
			end
     	candidates=score_elem(bests)
      best_elem=select_best(candidates)
      best_elem.text.gsub(/\s(\s+)/,"") 
    end

    def score_elem(bests)
      bests.each do |elem|
        base_score=100
        str = "#{elem[:class]}#{elem[:id]}"
        base_score+=10 if str =~ REGEXES[:maybe_post]
        base_score-=20 if str =~ REGEXES[:not_post]
        base_score-=8  if elem_size(elem)<DEFAULT_OPTIONS[:min_text_length]
        elem["score"]=base_score.to_s
      end
			bests.map{|best| debug("#{best.name}.#{best[:class]} #{best[:id]}---score:#{best['score']}")}
      bests
    end

    def select_best(candidates)
      last_candidates=[]
      candidates=candidates.sort{|a,b| b["score"].to_i<=>a["score"].to_i}
      best_score=candidates.first["score"]
      candidates.delete_if{|c| c["score"]!=best_score}
      return candidates.first if candidates.size==1
      candidates.each do |p|
        flag=0
        candidates.each do |q|
          if is_contain(p,q) == true && p != q
            flag+=1
          end
        end
        last_candidates<<p if flag==0
      end
			if last_candidates.size==1
				debug("best_one:#{last_candidates.first.name}.#{last_candidates.first[:class]} #{last_candidates.first[:id]}")
      	return last_candidates.first 
			end
      last_candidates.each do |lc|
        lc["text_rate"] = (elem_size(lc)/elem_size(lc,'inner_html').to_f).to_s
      end
			last_candidates.map{|lc| debug("best_one:#{lc.name}.#{lc[:class]} #{lc[:id]}---text_rate:#{lc['text_rate']}")}
      last_candidates.sort{|a,b| b["text_rate"].to_f<=>a["text_rate"].to_f}.first
    end

    def most_likely_posts(better_post)
      most_likely_posts=[]
      better_post.each do |q|
          flag=0
          better_post.each do |p|
               if is_contain(p,q) == true && p != q
                  flag+=1
               end
          end
          if flag == 0
            most_likely_posts << q
            debug("most_likelys:#{q.name}.#{q[:class]}.#{q[:id]}") 
          end
        end
      most_likely_posts.sort{|m,n| elem_size(n)<=>elem_size(m)}.first
    end
    
    def elem_size(elem,type='inner_text')
       return elem.text.gsub(/\s(\s+)/,"").size  if type=='inner_text'
       return elem.inner_html.gsub(/\s(\s+)/,"").size if type=='inner_html' 
    end

    def likely_posts
      h={}
      likely_posts=[]
      @html.css("div,tr,td").each do |elem|
          str = "#{elem[:class]}#{elem[:id]}"
          if str =~ REGEXES[:maybe_post]
            flag="#{elem.name},#{elem[:class]}"
            collect_likely_elem(h,flag,elem)
          end
       end
       h.delete_if{|k,v| v.size < DEFAULT_OPTIONS[:min_length]}
       h.map{|k,v| likely_posts << v.first}
			 likely_posts.map{|lp| debug("likely_posts:#{lp.name}.#{lp[:class]} #{lp[:id]}")}
       likely_posts
    end

		def collect_likely_elem(h,flag,elem)
				flag.split(/ /).each do |item|
					h.map do |k,v|
						h[k] << elem if k =~ Regexp.new(item)
					end
				end
				h[flag] = ([] << elem)
		end

    def remove_script_and_style!
      @html.css("script, style").each { |i| i.remove }
    end

    def remove_unlikely_candidates!
      @html.css("*").each do |elem|
        str = "#{elem[:class]}#{elem[:id]}"
        if str =~ REGEXES[:unlikelyCandidatesRe] && str !~ REGEXES[:maybe_post] && elem.name.downcase != 'body'
					debug("Removing unlikely candidate - #{str}")
          elem.remove
        end
      end
    end
    
    def transform_misused_divs_into_p!
      @html.css("*").each do |elem|
        if elem.name.downcase == "div"
          if elem.inner_html !~ REGEXES[:divToPElementsRe]
						#debug("Altering div(##{elem[:id]}.#{elem[:class]}) to p");
            elem.name = "p"
          end
        end
      end
    end

    def is_contain(p,q)
      p.css("div,tr,td").each do |item|
        return true if item.name == q.name && item[:class] == q[:class]
      end
      return false
    end

    def debug(str)
      puts str if options[:debug]
    end
    
   end
end


#require 'open-uri'
#include ForumPost
#uri = 'http://topic.csdn.net/u/20110718/17/f1a523fb-8c65-4510-a094-daf7bd2698cf.html?50656'
#uri = 'http://bbs.lampchina.net/thread-29528-1-1.html'
#uri = 'http://bbs.55bbs.com/thread-5662509-1-1.html'

#uri='http://topic.csdn.net/u/20110803/11/7ef08712-129d-4971-88a4-4bd0b712c804.html?90401'
#f = open(uri).read
#charset = adjudge_html_charset(f)
#source = convert_to_utf8(f,charset)
#d = Document.new(source)
#puts d.content
