require 'ddtrace/ext/sql'

require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'mysql.query', 'postgres.query', ... spans.
      module ActiveRecord
        def self.instrument
          # ActiveRecord is instrumented only if it's available
          return unless defined?(::ActiveRecord)

          # subscribe when the active record query has been processed
          ::ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
            sql(*args)
          end
        end

        def self.sql(_name, start, finish, _id, payload)
          return unless ::ActiveRecord::Base.connection_handler.active_connections?
          Datadog::Tracer.log.info('ActiveRecord connection not present')
          Datadog::Tracer.log.debug(payload.inspect)
          tracer = Datadog.configuration[:rails][:tracer]
          database_service = Datadog.configuration[:rails][:database_service]
          adapter_name = Datadog::Contrib::Rails::Utils.adapter_name
          database_name = Datadog::Contrib::Rails::Utils.database_name
          span_type = Datadog::Ext::SQL::TYPE

          span = tracer.trace(
            "#{adapter_name}.query",
            resource: payload.fetch(:sql),
            service: database_service,
            span_type: span_type
          )

          # find out if the SQL query has been cached in this request. This meta is really
          # helpful to users because some spans may have 0ns of duration because the query
          # is simply cached from memory, so the notification is fired with start == finish.
          # TODO[manu]: this feature has been merged into master but has not yet released.
          # We're supporting this action as a best effort, but we should add a test after
          # a new version of Rails is out.
          cached = payload[:cached]

          # the span should have the query ONLY in the Resource attribute,
          # so that the ``sql.query`` tag will be set in the agent with an
          # obfuscated version
          span.span_type = Datadog::Ext::SQL::TYPE
          span.set_tag('rails.db.vendor', adapter_name)
          span.set_tag('rails.db.name', database_name)
          span.set_tag('rails.db.cached', cached) if cached
          span.start_time = start
          span.finish(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
