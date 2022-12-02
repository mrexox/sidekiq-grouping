# frozen_string_literal: true

module Sidekiq
  module Grouping
    class Redis
      PLUCK_SCRIPT = <<-SCRIPT
        local pluck_values = redis.call('lpop', KEYS[1], ARGV[1]) or {}
        if #pluck_values > 0 then
          redis.call('srem', KEYS[2], unpack(pluck_values))
        end
        return pluck_values
      SCRIPT

      def push_msg(name, msg, remember_unique: false)
        redis do |conn|
          conn.multi do |pipeline|
            sadd = pipeline.respond_to?(:sadd?) ? :sadd? : :sadd
            pipeline.public_send(sadd, ns("batches"), name)
            pipeline.rpush(ns(name), msg)
            if remember_unique
              pipeline.public_send(
                sadd,
                unique_messages_key(name),
                msg
              )
            end
          end
        end
      end

      def enqueued?(name, msg)
        redis do |conn|
          conn.sismember(unique_messages_key(name), msg)
        end
      end

      def batch_size(name)
        redis { |conn| conn.llen(ns(name)) }
      end

      def batches
        redis { |conn| conn.smembers(ns("batches")) }
      end

      def pluck(name, limit)
        keys = [ns(name), unique_messages_key(name)]
        args = [limit]
        redis { |conn| conn.eval PLUCK_SCRIPT, keys, args }
      end

      def get_last_execution_time(name)
        redis { |conn| conn.get(ns("last_execution_time:#{name}")) }
      end

      def set_last_execution_time(name, time)
        redis do |conn|
          conn.set(ns("last_execution_time:#{name}"), time.to_json)
        end
      end

      def lock(name)
        redis do |conn|
          id = ns("lock:#{name}")
          conn.set(id, true, nx: true, ex: Sidekiq::Grouping::Config.lock_ttl)
        end
      end

      def delete(name)
        redis do |conn|
          conn.del(ns("last_execution_time:#{name}"))
          conn.del(ns(name))
          conn.srem(ns("batches"), name)
        end
      end

      private

      def unique_messages_key(name)
        ns("#{name}:unique_messages")
      end

      def ns(key = nil)
        "batching:#{key}"
      end

      def redis(&block)
        Sidekiq.redis(&block)
      end
    end
  end
end
