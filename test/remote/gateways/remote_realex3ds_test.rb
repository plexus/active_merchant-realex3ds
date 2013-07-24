require File.expand_path('../../../test_helper', __FILE__)

require 'active_merchant/billing/gateways/realex3ds'

class RemoteRealexTest < Test::Unit::TestCase

  def valid_card_attributes
    {:first_name => 'Steve', :last_name => 'Smith', :month => '9', :year => '2010', :type => 'visa', :number => '4242424242424242'}
  end

  def create_card(fixture)
    CreditCard.new valid_card_attributes.merge(fixtures(fixture))
  end

  def setup
    @gateway = Realex3dsGateway.new(fixtures(:realex_with_account))

    @gateway_with_account = Realex3dsGateway.new(fixtures(:realex_with_account))

    # Replace the card numbers with the test account numbers from Realex
    @visa            = create_card(:realex_visa)
    @visa_declined   = create_card(:realex_visa_declined)
    @visa_referral_b = create_card(:realex_visa_referral_b)
    @visa_referral_a = create_card(:realex_visa_referral_a)
    @visa_coms_error = create_card(:realex_visa_coms_error)

    @mastercard            = create_card(:realex_mastercard)
    @mastercard_declined   = create_card(:realex_mastercard_declined)
    @mastercard_referral_b = create_card(:realex_mastercard_referral_b)
    @mastercard_referral_a = create_card(:realex_mastercard_referral_a)
    @mastercard_coms_error = create_card(:realex_mastercard_coms_error)

    @amount = 10000
  end

  def test_realex_purchase
    [ @visa, @mastercard ].each do |card|

      response = @gateway.purchase(@amount, card,
        :order_id => generate_unique_id,
        :description => 'Test Realex Purchase',
        :billing_address => {
          :zip => '90210',
          :country => 'US'
        }
      )

      assert_not_nil response
      assert_success response
      assert response.test?
      assert response.authorization.length > 0
      assert_equal 'Successful', response.message
    end
  end

  def test_realex_purchase_with_invalid_login
    gateway = Realex3dsGateway.new(
      :login => 'invalid',
      :password => 'invalid'
    )
    response = gateway.purchase(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'Invalid login test'
    )

    assert_not_nil response
    assert_failure response

    assert_equal '504', response.params['result']
    assert_equal "There is no such merchant id. Please contact realex payments if you continue to experience this problem.", response.message
  end

  def test_realex_purchase_with_invalid_account
    @gateway_with_invalid_account = Realex3dsGateway.new(fixtures(:realex_with_account).merge(:account => "thisdoesnotexist"))
    response = @gateway_with_invalid_account.purchase(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'Test Realex purchase with invalid acocunt'
    )

    assert_not_nil response
    assert_failure response

    assert_equal '506', response.params['result']
    assert_equal "There is no such merchant account. Please contact realex payments if you continue to experience this problem.", response.message
  end

  def test_realex_purchase_declined

    [ @visa_declined, @mastercard_declined ].each do |card|

      response = @gateway.purchase(@amount, card,
        :order_id => generate_unique_id,
        :description => 'Test Realex purchase declined'
      )
      assert_not_nil response
      assert_failure response

      assert_equal '101', response.params['result']
      assert_equal response.params['message'], response.message
    end

  end

  def test_realex_purchase_referral_b
    [ @visa_referral_b, @mastercard_referral_b ].each do |card|

      response = @gateway.purchase(@amount, card,
        :order_id => generate_unique_id,
        :description => 'Test Realex Referral B'
      )
      assert_not_nil response
      assert_failure response
      assert response.test?
      assert_equal '102', response.params['result']
      assert_equal Realex3dsGateway::DECLINED, response.message
    end
  end

  def test_realex_purchase_referral_a
    [ @visa_referral_a, @mastercard_referral_a ].each do |card|

      response = @gateway.purchase(@amount, card,
        :order_id => generate_unique_id,
        :description => 'Test Realex Rqeferral A'
      )
      assert_not_nil response
      assert_failure response
      assert_equal '103', response.params['result']
      assert_equal Realex3dsGateway::DECLINED, response.message
    end

  end

  def test_realex_purchase_coms_error

    [ @visa_coms_error, @mastercard_coms_error ].each do |card|

      response = @gateway.purchase(@amount, card,
        :order_id => generate_unique_id,
        :description => 'Test Realex coms error'
      )

      assert_not_nil response
      assert_failure response

      assert_equal '200', response.params['result']
      # assert_equal '205', response.params['result']
      # will be a 205 in production
      # will be a 200 error in test arg.
      assert_equal Realex3dsGateway::BANK_ERROR, response.message
    end

  end

  def test_realex_ccn_error
    visa = @visa.clone
    visa.number = '5'

    response = @gateway.purchase(@amount, visa,
      :order_id => generate_unique_id,
      :description => 'Test Realex ccn error'
    )

    assert_not_nil response
    assert_failure response

    # Looking at the API this should actually be "509 - Invalid credit card length" but hey..
    assert_equal '508', response.params['result']
    assert_equal "Invalid data in CC number field.", response.message
  end

  def test_realex_expiry_month_error
    @visa.month = 13

    response = @gateway.purchase(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'Test Realex expiry month error'
    )
    assert_not_nil response
    assert_failure response

    assert_equal '509', response.params['result']
    assert_equal "Expiry date invalid", response.message
  end

  def test_realex_expiry_year_error
    @visa.year = 2005

    response = @gateway.purchase(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'Test Realex expiry year error'
    )
    assert_not_nil response
    assert_failure response

    assert_equal '509', response.params['result']
    assert_equal "Expiry date invalid", response.message
  end

  def test_invalid_credit_card_name
    @visa.first_name = ""
    @visa.last_name = ""

    response = @gateway.purchase(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'test_chname_error'
    )
    assert_not_nil response
    assert_failure response

    assert_equal '502', response.params['result']
    assert_equal "Mandatory field not present - cannot continue. Please check the Developer Documentation for mandatory fields", response.message
  end

  def test_cvn
    @visa_cvn = @visa.clone
    @visa_cvn.verification_value = "111"
    response = @gateway.purchase(@amount, @visa_cvn,
      :order_id => generate_unique_id,
      :description => 'test_cvn'
    )
    assert_not_nil response
    assert_success response
    assert response.authorization.length > 0
  end

  def test_customer_number
    response = @gateway.purchase(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'test_cust_num',
      :customer => 'my customer id'
    )
    assert_not_nil response
    assert_success response
    assert response.authorization.length > 0
  end

  def test_realex_authorize
    response = @gateway.authorize(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'Test Realex Purchase',
      :billing_address => {
        :zip => '90210',
        :country => 'US'
      }
    )

    assert_not_nil response
    assert_success response
    assert response.test?
    assert response.authorization.length > 0
    assert_equal 'Successful', response.message
  end

  def test_realex_authorize_then_capture
    order_id = generate_unique_id

    auth_response = @gateway.authorize(@amount, @visa,
      :order_id => order_id,
      :description => 'Test Realex Purchase',
      :billing_address => {
        :zip => '90210',
        :country => 'US'
      }
    )

    capture_response = @gateway.capture(@amount, auth_response.authorization,
      :order_id => order_id,
      :pasref => auth_response.params['pasref']
    )

    assert_not_nil capture_response
    assert_success capture_response
    assert capture_response.test?
    assert capture_response.authorization.length > 0
    assert_equal 'Successful', capture_response.message
    assert_match /Settled Successfully/, capture_response.params['message']
  end

  def test_realex_purchase_then_void
    order_id = generate_unique_id

    purchase_response = @gateway.purchase(@amount, @visa,
      :order_id => order_id,
      :description => 'Test Realex Purchase',
      :billing_address => {
        :zip => '90210',
        :country => 'US'
      }
    )

    void_response = @gateway.void(purchase_response.authorization,
      :order_id => order_id,
      :pasref => purchase_response.params['pasref']
    )

    assert_not_nil void_response
    assert_success void_response
    assert void_response.test?
    assert void_response.authorization.length > 0
    assert_equal 'Successful', void_response.message
    assert_match /Voided Successfully/, void_response.params['message']
  end

  def test_realex_purchase_then_credit
    order_id = generate_unique_id

    @gateway_with_refund_password = Realex3dsGateway.new(fixtures(:realex_with_account).merge(:rebate_secret => 'refund'))

    purchase_response = @gateway_with_refund_password.purchase(@amount, @visa,
      :order_id => order_id,
      :description => 'Test Realex Purchase',
      :billing_address => {
        :zip => '90210',
        :country => 'US'
      }
    )

    rebate_response = @gateway_with_refund_password.credit(@amount, purchase_response.authorization,
      :order_id => order_id,
      :pasref => purchase_response.params['pasref']
    )

    assert_not_nil rebate_response
    assert_success rebate_response
    assert rebate_response.test?
    assert rebate_response.authorization.length > 0
    assert_equal 'Successful', rebate_response.message
  end

  def test_realex_response_body
    response = @gateway.authorize(@amount, @visa, :order_id => generate_unique_id)
    assert_not_nil response.body
  end

  def test_realex_authorize_with_3dsecure
    response = @gateway.authorize(@amount, @visa,
      :order_id => generate_unique_id,
      :description => 'Test Realex Purchase',
      :billing_address => {
        :zip => '90210',
        :country => 'US'
      },
      :three_d_secure => true
    )

    assert_not_nil response
    assert_success response
    assert response.params['pareq'].length > 0
    assert response.params['enrolled'].length > 0
    assert response.params['enrolled'] == "Y"

    assert_equal response.params['url'], 'https://dropit.3dsecure.net:9443/PIT/ACS'

    assert_equal 'Successful', response.message
  end

#  def test_realex_purchase_with_3dsecure
#    order_id = generate_unique_id
#    response = @gateway.authorize(@amount, @visa,
#      :order_id => order_id,
#      :description => 'Test Realex Purchase',
#      :billing_address => {
#        :zip => '90210',
#        :country => 'US'
#      },
#      :three_d_secure => true
#    )
#
#    pareq = response.params['pareq']
#
#    response = @gateway.purchase(@amount, @visa,
#      :order_id => order_id,
#      :description => 'Test Realex Purchase',
#      :billing_address => {
#        :zip => '90210',
#        :country => 'US'
#      },
#      :three_d_secure_auth => {
#        :pa_res => pareq
#      }
#    )
#
#
#    assert_not_nil response
#    assert_success response
#    assert response.params['pareq'].length > 0
#    assert response.params['enrolled'].length > 0
#
#    assert_equal 'Successful', response.message
#  end

  # response timestamp=\"20100303191232\">\r\n<merchantid>exoftwaretest</merchantid>\r\n<account>internet</account>\r\n<orderid>edeac18e066b7208bbdec24c105c17e1</orderid>\r\n<result>00</result>\r\n<message>Successful</message>\r\n<pasref>69deeba5cc294cbba3e3becc016fd3ed</pasref>\r\n<authcode></authcode>\r\n<batchid></batchid>\r\n<timetaken>0</timetaken>\r\n<processingtimetaken></processingtimetaken>\r\n<md5hash>37f71f37cb3a7eb2e138f46d6fe9cbcb</md5hash>\r\n<sha1hash>1aa79d2d8621c8d2e4c80a752c19c75f717ff8b7</sha1hash>\r\n</response>\r\n", @authorization=nil, @success=true>

  def test_realex_store_user
    options = {
      :order_id => generate_unique_id,
      :user => {
        :id => generate_unique_id,
        :first_name => 'John',
        :last_name => 'Smith'
      }
    }
    response = @gateway.store_user(options)

    assert_not_nil response
    assert_success response
    assert_equal 'Successful', response.message
  end

  def test_realex_store_card
    options = {
      :order_id => generate_unique_id,
      :user => {
        :id => generate_unique_id,
        :first_name => 'John',
        :last_name => 'Smith'
      }
    }
    response = @gateway.store_user(options)

    options.merge!(:order_id => generate_unique_id)
    store_card_response = @gateway.store(@visa, options)

    assert_not_nil store_card_response
    assert_success store_card_response
    assert_equal 'Successful', store_card_response.message
  end

  def test_realex_receipt_in
    options = {
      :order_id => generate_unique_id,
      :user => {
        :id => generate_unique_id,
        :first_name => 'John',
        :last_name => 'Smith'
      }
    }
    response = @gateway.store_user(options)

    options.merge!(:order_id => generate_unique_id, :payment_method => 'visa01')
    store_card_response = @gateway.store(@visa, options)

    options.merge!({
      :order_id => generate_unique_id,
      :payment_method => 'visa01'
    })
    receipt_in_response = @gateway.recurring(@amount, @visa, options)

    assert_not_nil receipt_in_response
    assert_success receipt_in_response
    assert_equal 'Successful', receipt_in_response.message
  end

  def test_realex_unstore_card
    options = {
      :order_id => generate_unique_id,
      :user => {
        :id => generate_unique_id,
        :first_name => 'John',
        :last_name => 'Smith'
      }
    }
    response = @gateway.store_user(options)

    options.merge!(:order_id => generate_unique_id, :payment_method => generate_unique_id)
    store_card_response = @gateway.store(@visa, options)

    unstore_card_response = @gateway.unstore(@visa, options)

    assert_not_nil unstore_card_response
    assert_success unstore_card_response
    assert_equal 'Successful', unstore_card_response.message
  end

end
