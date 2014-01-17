class RedisStore
  STORE_PREFIX="nmdb3:"

  def initialize
  end

  def set(key, value, expire = nil)
    if expire
      redis.setex(STORE_PREFIX+key, expire, value)
    else
      redis.set(STORE_PREFIX+key, value)
    end
  end

  def expire(key, new_expire)
    redis.expire(STORE_PREFIX+key, new_expire)
  end

  def persist(key)
    redis.persist(STORE_PREFIX+key)
  end

  def get(key)
    redis.get(STORE_PREFIX+key)
  end

  def self.mget(*keys)
    keys = [*keys].map { |x| STORE_PREFIX+x }
    Hash[*keys.zip(data.mget(keys)).flatten]
  end

  def keys(pattern = "*")
    redis.keys(STORE_PREFIX+pattern).map { |x| x[STORE_PREFIX.size..-1]}
  end

  def del(key)
    redis.del(STORE_PREFIX+key)
  end

  def incr(key)
    redis.incr(STORE_PREFIX+key)
  end

  def exists?(key)
    redis.exists?(STORE_PREFIX+key)
  end

  def redis
    @redis ||= Redis.new
  end
end

module Rails
  def self.rcache
    @@redis_store ||= RedisStore.new
  end
end
