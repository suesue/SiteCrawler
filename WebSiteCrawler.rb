#!/usr/bin/ruby

require 'open-uri'
require 'uri'
require 'pathname'
require 'fileutils'
require 'nokogiri'


module SS
module WebSiteCrawler

	class WebSite
		attr_reader :homepage_uri
		attr_reader :pages

		def initialize( homepage_url )
			@homepage_uri = URI.parse( homepage_url )
			@pages = {}
		end

		def crawl( local_store, ignore = false )
			local_store.home = @homepage_uri.host

			stack = Stack.new
			stack.push @homepage_uri

			while !stack.empty? and ( uri = stack.pop ) do
				stack << download( local_store, uri, ignore )
			end
		end

		def download( local_store, uri, ignore = false )
			return if @pages[ uri ]

			contents = Contents.new( uri )
			contents.download
			file = local_store.store( contents, ignore )
			return unless file

			finder = HtmlLinkFinder.new( contents )
			@pages[ uri ] = finder

			finder.list
		end

#		def download_x( local_store, uri )
#			return if @pages[ uri ]
#
#			Contents.new( uri ).download do |contents|
#				@pages[ uri ] = local_store.store( contents )
#
#				HtmlLinkFinder.new( contents ).list do |f, u|
#					download_x local_store, u
#				end
#			end
#		end

	end

	class LocalStore
		attr_reader :base_dir
		attr_accessor :home

		def initialize( dir = nil, home = nil )
			if dir then
				raise if File.file?( dir )
			else
				dir = "."
			end

			path = File.expand_path( dir )
			Dir.mkdir( path ) unless File.directory?( path )
			@base_dir = Pathname.new( path )

			@home = home
		end

		def store( contents, ignore = false )
			raise unless @home

			path = File.join( @base_dir.realpath, @home, Pathname.new( contents.uri.path ) )
			contents.attach path

			if File.file?( path ) then
				raise unless ignore
				return nil
			end

			p = Pathname.new( path )
			FileUtils.makedirs( p.parent ) unless File.directory?( p.parent )

			open( p, "w" ) do |file|
				puts "+ #{contents.uri} => #{p}"
				contents.save file
			end

			path
		end

	end

	class Contents
		attr_reader :uri
		attr_reader :charset
		attr_reader :body
		attr_reader :local_path

		def initialize( uri )
			raise unless uri

			@uri = uri
			@charset = nil
			@body = nil
		end

		def download
			@charset = nil
			@body = nil

			open( @uri ) do |f|
				@charset = f.charset
				@body = f.read
			end

			yield self if block_given?
		end

		def attach( path )
			raise unless path
			@local_path = path
		end

		def save( out )
			raise unless @body

			open( out, "w" ) do |file|
				file.write @body
			end
		end

	end

	class HtmlLinkFinder
		attr_reader :contents

		def initialize( contents )
			raise unless contents
			@contents = contents
		end

		def list( &block )
			doc = Nokogiri::HTML.parse( @contents.body, nil, @contents.charset )
			find_from_doc doc, &block
		end

		def find_from_doc( doc, &block )
			puts block
			links = block ? nil: []

			find_by_xpath doc, links, '//a/@href', &block
			find_by_xpath doc, links, '//img/@src', &block
			find_by_xpath doc, links, '//script/@src', &block
			find_by_xpath doc, links, '//style/@src', &block
			find_by_xpath doc, links, '//link/@href', &block

			links
		end

		def find_by_xpath( doc, links, xpath )
			begin
				doc.xpath( xpath ).each do |attr|
					#puts "link: #{attr.value}"
					link_uri = to_uri( attr.value )
					if link_uri then
						link_uri.query = nil
						link_uri.fragment = nil

						if block_given? then
							yield self, link_uri
						else
							links << link_uri
						end
					end
				end
			rescue => e
				puts "\t* #{@contents.uri} may broken; #{e}"
			end
		end

		def to_uri( path )
			uri = URI.parse( path )
			if uri.relative? then
				# relative
				#puts "#{self.class.name}#to_url: #{@contents.uri + uri}"
				puts "\t+ #{@contents.uri + uri}"
				@contents.uri + uri
			elsif uri.opaque then
				# absolute but mailto, news, urn, ...
				puts "\t- #{path}"
				nil
			elsif uri.scheme == @contents.uri.scheme and uri.host == @contents.uri.host then
				# absolute but same host
				uri
			else
				# absolute
#				case uri.scheme
#				when "http", "https" then
#					#puts "#{self.class.name}#to_url: #{uri}"
#					puts "\t+ #{path}"
#					uri
#				else
#					#puts "#{self.class.name}#to_url: DISCARD #{path}"
					puts "\t- #{path}"
					nil
#				end
			end
		end

	end

	class StackNode
		attr_accessor :content
		attr_accessor :next_
	end

	class Stack
		attr_reader :first
		attr_reader :last

		def <<( elements )
			return unless elements
			elements.each do |element|
				push element
			end
		end

		def push( element )
			node = StackNode.new
			node.content = element

			if @last then
				@last.next_ = node
				@last = node
			elsif @first then
				@first.next_ = node
				@last = node
			else
				@first = node
			end
		end

		def pop
			node = nil
			if @first.nil? then
				;
			elsif @last.nil? then
				node = @first
				@first = nil
			else
				node = @first
				@first = @first.next_
			end
			node ? node.content: nil
		end

		def empty?
			@first.nil?
		end

	end

end
end


if __FILE__ == $0 then
	local_store = SS::WebSiteCrawler::LocalStore.new
	ARGV.each do |arg|
		SS::WebSiteCrawler::WebSite.new( arg ).crawl( local_store, true )
	end
end
