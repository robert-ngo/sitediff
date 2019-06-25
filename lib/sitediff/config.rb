# frozen_string_literal: true

require 'sitediff/exception'
require 'sitediff/sanitize'
require 'pathname'
require 'yaml'

class SiteDiff
  # SiteDiff Configuration.
  class Config
    # Default config file.
    DEFAULT_FILENAME = 'sitediff.yaml'

    # Default SiteDiff config.
    DEFAULT_CONFIG = {
      'before' => {},
      'after' => {},
      'paths' => []
    }.freeze

    # keys allowed in configuration files
    CONF_KEYS = Sanitizer::TOOLS.values.flatten(1) +
                %w[paths before after before_url after_url includes curl_opts]

    class InvalidConfig < SiteDiffException; end
    class ConfigNotFound < SiteDiffException; end

    # Takes a Hash and normalizes it to the following form by merging globals
    # into before and after. A normalized config Hash looks like this:
    #
    #     paths:
    #     - /about
    #
    #     before:
    #       url: http://before
    #       selector: body
    #       dom_transform:
    #       - type: remove
    #         selector: script
    #
    #     after:
    #       url: http://after
    #       selector: body
    #
    def self.normalize(conf)
      tools = Sanitizer::TOOLS

      # merge globals
      %w[before after].each do |pos|
        conf[pos] ||= {}
        tools[:array].each do |key|
          conf[pos][key] ||= []
          conf[pos][key] += conf[key] if conf[key]
        end
        tools[:scalar].each { |key| conf[pos][key] ||= conf[key] }
        conf[pos]['url'] ||= conf[pos + '_url']
        conf[pos]['curl_opts'] = conf['curl_opts']
      end
      # normalize paths
      conf['paths'] = Config.normalize_paths(conf['paths'])

      conf.select { |k, _v| %w[before after paths curl_opts].include? k }
    end

    # Merges two normalized Hashes according to the following rules:
    # 1 paths are merged as arrays.
    # 2 before and after: for each subhash H (e.g. ['before']['dom_transform']):
    #   a)  if first[H] and second[H] are expected to be arrays, their values
    #       are merged as such,
    #   b)  if first[H] and second[H] are expected to be scalars, the value for
    #       second[H] is kept if and only if first[H] is nil.
    #
    # For example, merge(h1, h2) results in h3:
    #
    # (h1) before: {selector: foo, sanitization: [pattern: foo]}
    # (h2) before: {selector: bar, sanitization: [pattern: bar]}
    # (h3) before: {selector: foo, sanitization: [pattern: foo, pattern: bar]}
    def self.merge(first, second)
      result = { 'paths' => {}, 'before' => {}, 'after' => {} }
      # Rule 1.
      result['paths'] = (first['paths'] || []) + (second['paths'] || [])
      %w[before after].each do |pos|
        unless first[pos]
          result[pos] = second[pos] || {}
          next
        end
        result[pos] = first[pos].merge!(second[pos]) do |key, a, b|
          # Rule 2a.
          result[pos][key] = if Sanitizer::TOOLS[:array].include? key
                               (a || []) + (b || [])
                             else
                               a || b # Rule 2b.
                             end
        end
      end
      result
    end

    # Creates a SiteDiff Config object.
    def initialize(file, dir)
      # Fallback to default config filename, if none is specified.
      file = File.join(dir, DEFAULT_FILENAME) if file.nil?
      unless File.exist?(file)
        path = File.expand_path(file)
        raise InvalidConfig, "Missing config file #{path}."
      end
      @config = Config.merge(DEFAULT_CONFIG, Config.load_conf(file))
    end

    def before
      @config['before']
    end

    def after
      @config['after']
    end

    def paths
      @config['paths']
    end

    def paths=(paths)
      @config['paths'] = Config.normalize_paths(paths)
    end

    # Checks if the configuration is usable for diff-ing.
    def validate(opts = {})
      opts = { need_before: true }.merge(opts)

      raise InvalidConfig, "Undefined 'before' base URL." if \
        opts[:need_before] && !before['url']
      raise InvalidConfig, "Undefined 'after' base URL." unless after['url']
      raise InvalidConfig, "Undefined 'paths'." unless paths && !paths.empty?
    end

    private

    def self.normalize_paths(paths)
      paths ||= []
      paths.map { |p| (p[0] == '/' ? p : "/#{p}").chomp }
    end

    # reads a YAML file and raises an InvalidConfig if the file is not valid.
    def self.load_raw_yaml(file)
      SiteDiff.log "Reading config file: #{Pathname.new(file).expand_path}"
      conf = YAML.load_file(file) || {}

      unless conf.is_a? Hash
        raise InvalidConfig, "Invalid configuration file: '#{file}'"
      end

      conf.each_key do |k, _v|
        unless CONF_KEYS.include? k
          raise InvalidConfig, "Unknown configuration key (#{file}): '#{k}'"
        end
      end

      conf
    end

    # loads a single YAML configuration file, merges all its 'included' files
    # and returns a normalized Hash.
    def self.load_conf(file, visited = [])
      # don't get fooled by a/../a/ or symlinks
      file = File.realpath(file)
      if visited.include? file
        raise InvalidConfig, "Circular dependency: #{file}"
      end

      conf = load_raw_yaml(file) # not normalized yet
      visited << file

      # normalize and merge includes
      includes = conf['includes'] || []
      conf = Config.normalize(conf)
      includes.each do |dep|
        # include paths are relative to the including file.
        dep = File.join(File.dirname(file), dep)
        conf = Config.merge(conf, load_conf(dep, visited))
      end
      conf
    end
  end
end
