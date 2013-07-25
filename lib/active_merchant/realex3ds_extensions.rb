class ActiveMerchant::Billing::Response
  attr_reader :body, :pa_req, :md, :acs_url

  def three_d_secure?
    @three_d_secure
  end

  def enrolled?
    @three_d_secure_enrolled
  end

  alias initialize_original initialize

  def initialize(success, message, params = {}, options = {})
    initialize_original(success, message, params, options)

    @body = options[:body]
    # 3D 'Three D' Secure
    @three_d_secure = options[:three_d_secure]
    @three_d_secure_enrolled = options[:three_d_secure_enrolled]
    @pa_req = options[:pa_req]
    @xid = options[:xid]
    @acs_url = options[:acs_url]
  end
end
