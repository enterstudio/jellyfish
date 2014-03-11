
require 'jellyfish/json'

module Jellyfish
  class Swagger
    include Jellyfish
    attr_reader :swagger_apis, :jellyfish_apis
    controller_include Jellyfish::NormalizedPath, Module.new{
      def block_call argument, block
        headers_merge 'Content-Type' => 'application/json; charset=utf-8'
        super
      end
    }

    get '/' do
      [Jellyfish::Json.encode(
        'apiVersion'     => '1.0.0'               ,
        'swaggerVersion' => '1.2'                 ,
        'info'           => jellyfish.swagger_info,
        'apis'           => jellyfish.swagger_apis)]
    end

    get %r{\A/(?<name>.+)\Z} do |match|
      name     = "/#{match[:name]}"
      basePath = "#{request.scheme}://#{request.host_with_port}"

      apis = jellyfish.jellyfish_apis[name].map{ |nickname, operations|
        {'path' => nickname, 'operations' => operations}
      }

      [Jellyfish::Json.encode(
        'apiVersion'     => '1.0.0'                   ,
        'swaggerVersion' => '1.2'                     ,
        'basePath'       => basePath                  ,
        'resourcePath'   => name                      ,
        'produces'       => jellyfish.swagger_produces,
        'apis'           => apis                      )]
    end

    def swagger_info
      if app.respond_to?(:info)
        app.info
      else
        {}
      end
    end

    def swagger_produces
      if app.respond_to?(:swagger_produces)
        app.swagger_produces
      else
        []
      end
    end

    def swagger_apis
      @swagger_apis ||= jellyfish_apis.keys.map do |name|
        {'path' => name}
      end
    end

    def jellyfish_apis
      @jellyfish_apis ||= app.routes.flat_map{ |meth, routes|
        routes.map{ |(path, _, meta)| operation(meth, path, meta) }
      }.group_by{ |api| api['path'] }.inject({}){ |r, (path, operations)|
        r[path] = operations.group_by{ |op| op['nickname'] }
        r
      }
    end

    def operation meth, path, meta
      if path.respond_to?(:source)
        nick = nickname(path)
        {'path'       => swagger_path(nick)    ,
         'method'     => meth.to_s.upcase      ,
         'nickname'   => nick                  ,
         'summary'    => meta[:summary]        ,
         'notes'      => meta[:notes]          ,
         'parameters' => parameters(path, meta)}
      else
        nick = swagger_path(path)
        {'path'       => nick,
         'method'     => meth.to_s.upcase      ,
         'nickname'   => nick                  ,
         'summary'    => meta[:summary]        ,
         'notes'      => meta[:notes]          ,
         'parameters' => {}}
      end
    end

    def swagger_path nickname
      nickname[%r{^/[^/]+}]
    end

    def nickname path
      if path.respond_to?(:source)
        path.source.gsub(param_pattern, '{\1}').gsub(/\\\w+/, '')
      else
        path.to_s
      end
    end

    def parameters path, meta
      Hash[path.source.scan(param_pattern)].map{ |name, pattern|
        path_params(name, pattern, meta)
      }
    end

    def path_params name, pattern, meta
      params = (meta[:parameters] || {})[name.to_sym] || {}
      {'name'        => name                                ,
       'type'        => params[:type] || param_type(pattern),
       'description' => params[:description]                ,
       'required'    => true                                ,
       'paramType'   => 'path'}
    end

    def param_type pattern
      if pattern.start_with?('\\d')
        if pattern.include?('.')
          'number'
        else
          'integer'
        end
      else
        'string'
      end
    end

    def param_pattern
       /\(\?<(\w+)>([^\)]+)\)/
    end
  end
end
