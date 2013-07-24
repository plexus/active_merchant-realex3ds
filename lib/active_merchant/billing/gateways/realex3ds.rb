require 'rexml/document'
require 'digest/sha1'

module ActiveMerchant
  module Billing
    # For more information on the Realex Payment Gateway visit their site {realexpayments.com}[http://realexpayments.com]. 
    # Realex is the leading gateway in Ireland
    #
    # === Merchant ID and Password
    #
    # To be able to use this library you will need to obtain an account from Realex, you can find contact them
    # via their website.
    #
    # === Caveats
    #
    # Realex requires that you specify the account to which your transactions are made.
    #
    #   gateway = ActiveMerchant::Billing::Realex3dsGateway.new(:login => 'xxx', :password => 'xxx', :acction => 'xxx') 
    #
    # If you wish to accept multiple currencies, you need to create an account per currency. 
    # This you would need to handle within your application logic.
    # Again, contact Realex for more information.
    #
    # They also require accepting payment from a Diners card (Mastercard) go through a different account.
    #
    # Realex also requires that you send several (extra) required identifiers with credit and void methods
    #
    # * order_id
    # * pasref
    # * authorization
    #
    # The pasref can be accessed from the response params. i.e.
    #   response.params['pasref']
    #
    # === Testing
    # 
    # Realex provide test card numbers on a per-account basis, you will need to request these.
    # Then if you copy the fixtures file that comes with this library to ~/.active_merchant/fixtures.yml
    # you can add in the required card number (and account) fixtures.
    #
    class Realex3dsGateway < Gateway
      URL = 'https://epage.payandshop.com/epage-remote.cgi'
      THREE_D_SECURE_URL = 'https://epage.payandshop.com/epage-3dsecure.cgi'
      RECURRING_PAYMENTS_URL = "https://epage.payandshop.com/epage-remote-plugins.cgi"
      
      CARD_MAPPING = {
        'master'            => 'MC',
        'visa'              => 'VISA',
        'visa_delta'        => 'VISA',
        'visa_electron'     => 'VISA',
        'american_express'  => 'AMEX',
        'diners_club'       => 'DINERS',
        'switch'            => 'SWITCH',
        'solo'              => 'SWITCH',
        'laser'             => 'LASER'
      }
      
      self.money_format = :cents
      self.default_currency = 'EUR'
      self.supported_cardtypes = [ :visa, :master, :american_express, :diners_club, :switch, :solo, :laser ]
      self.supported_countries = [ 'IE', 'GB' ]
      self.homepage_url = 'http://www.realexpayments.com/'
      self.display_name = 'Realex'
           
      SUCCESS, DECLINED          = "Successful", "Declined"
      BANK_ERROR = REALEX_ERROR  = "Gateway is in maintenance. Please try again later."
      ERROR = CLIENT_DEACTIVATED = "Gateway Error"
      
      def initialize(options = {})
        requires!(options, :login, :password)
        options[:refund_hash] = Digest::SHA1.hexdigest(options[:rebate_secret]) if options.has_key?(:rebate_secret)
        @options = options
        super
      end  

      # Performs an authorization, which reserves the funds on the customer's credit card, but does not
      # charge the card.
      #
      # ==== Parameters
      #
      # * <tt>money</tt> -- The amount to be authorized. Either an Integer value in cents or a Money object.
      # * <tt>creditcard</tt> -- The CreditCard details for the transaction.
      # * <tt>options</tt> -- A hash of optional parameters.
      #
      # ==== Options
      #
      # * <tt>:order_id</tt> -- The application generated order identifier. (REQUIRED)
      #
      def authorize(money, creditcard, options = {})
        requires!(options, :order_id)

        if options[:three_d_secure]
          three_d_secure_request = build_3d_secure_verify_signature_or_enrolled_request("3ds-verifyenrolled", money, creditcard, options)
          three_d_secure_response = commit(three_d_secure_request, :three_d_secure)
          return three_d_secure_response if three_d_secure_response.enrolled?
        end
        
        request = build_purchase_or_authorization_request(:authorization, money, creditcard, options) 
        commit(request)
      end
      
      # Perform a purchase, which is essentially an authorization and capture in a single operation.
      #
      # ==== Parameters
      #
      # * <tt>money</tt> -- The amount to be purchased. Either an Integer value in cents or a Money object.
      # * <tt>creditcard</tt> -- The CreditCard details for the transaction.
      # * <tt>options</tt> -- A hash of optional parameters.
      #
      # ==== Options
      #
      # * <tt>:order_id</tt> -- The application generated order identifier. (REQUIRED)
      #
      def purchase(money, creditcard, options = {})
        requires!(options, :order_id)

        if options[:three_d_secure_auth]
          three_d_secure_request = build_3d_secure_verify_signature_or_enrolled_request("3ds-verifysig", money, creditcard, options)
          three_d_secure_response = commit(three_d_secure_request, :three_d_secure)
          result = three_d_secure_response.params['result']
          if result  == '00'
            status = three_d_secure_response.params['threedsecure_status'] 
            # success
            if status == 'Y' || status == 'A'
              # Y: 3d Secure complete.
              # A: ACS service aknowledges.              
              # not-liable. continue
              options[:three_d_secure_sig] = {}
              options[:three_d_secure_sig][:eci]  = three_d_secure_response.params['threedsecure_eci']
              options[:three_d_secure_sig][:xid]  = three_d_secure_response.params['threedsecure_xid']
              options[:three_d_secure_sig][:cavv] = three_d_secure_response.params['threedsecure_cavv']
              # TODO add option[:accept_liability_authentication_failed]
              # TODO add option[:accept_liability_acs_failure]

            elsif status == 'N'
              # password entered incorrectly
              # liable. abort?
              return Response.new(false, "3DSecure password entered incorrectly. Aborting transaction.",{},{})
            elsif status == 'U'
              # Bank ACS service having dificulty. 
              # liable. abort?
              return Response.new(false, "3DSecure Bank ACS service 500 errors. Aborting transaction.",{},{})
            end  
          elsif result == "110"
            # fail, message tampered with.
            return Response.new(false, "3DSecure message tampered. Aborting transaction.",{},{})
          else
            return Response.new(false, "Unknown 3DSecure Error.",{},{})
          end
        end
        
        if options[:three_d_secure] && !options[:three_d_secure_auth]
          three_d_secure_request = build_3d_secure_verify_signature_or_enrolled_request("3ds-verifyenrolled", money, creditcard, options)
          three_d_secure_response = commit(three_d_secure_request, :three_d_secure)
          return three_d_secure_response if three_d_secure_response.enrolled?
        end
        
        request = build_purchase_or_authorization_request(:purchase, money, creditcard, options)
        commit(request)
      end
      
      # Captures the funds from an authorized transaction.
      #
      # ==== Parameters
      #
      # * <tt>money</tt> -- The amount to be captured.  Either an Integer value in cents or a Money object.
      # * <tt>authorization</tt> -- The authorization returned from the previous authorize request.
      #
      # ==== Options
      #
      # * <tt>:order_id</tt> -- The application generated order identifier. (REQUIRED)
      # * <tt>:pasref</tt> -- The realex payments reference of the original transaction. (REQUIRED)
      #
      def capture(money, authorization, options = {})
        requires!(options, :pasref)
        requires!(options, :order_id)
        
        request = build_capture_request(authorization, options) 
        commit(request)
      end
      
      # Credit an account.
      #
      # This transaction is also referred to as a Refund (or Rebate) and indicates to the gateway that
      # money should flow from the merchant to the customer.
      #
      # ==== Parameters
      #
      # * <tt>money</tt> -- The amount to be credited to the customer. Either an Integer value in cents or a Money object.
      # * <tt>authorization</tt> - The authorization returned from the previous authorize request.
      # * <tt>options</tt> -- A hash of parameters.
      #
      # ==== Options
      #
      # * <tt>:order_id</tt> -- The application generated order identifier. (REQUIRED)
      # * <tt>:pasref</tt> -- The realex payments reference of the original transaction. (REQUIRED)
      #
      def credit(money, authorization, options = {})
        requires!(options, :order_id)
        requires!(options, :pasref)
        
        request = build_credit_request(money, authorization, options)
        commit(request)
      end
      
      # Void a previous transaction
      #
      # ==== Parameters
      #
      # * <tt>authorization</tt> - The authorization returned from the previous authorize request.
      #
      # ==== Options
      #
      # * <tt>:order_id</tt> -- The application generated order identifier. (REQUIRED)
      # * <tt>:pasref</tt> -- The realex payments reference of the original transaction. (REQUIRED)
      #
      def void(authorization, options = {})
        requires!(options, :order_id)
        requires!(options, :pasref)
        
        request = build_void_request(authorization, options) 
        commit(request)
      end

      # Recurring Payments
      
      def recurring(money, credit_card, options = {})
        requires!(options, :order_id)

        request = build_receipt_in_request(money, credit_card, options) 
        commit(request, :recurring)
      end

      def store(credit_card, options = {})
        requires!(options, :order_id)
        request = build_new_card_request(credit_card, options)
        commit(request, :recurring)
      end

      def unstore(creditcard, options = {})     
        request = build_cancel_card_request(creditcard, options)
        commit(request, :recurring)
      end

      def store_user(options = {})
        requires!(options, :order_id)
        request = build_new_payee_request(options)
        commit(request, :recurring)
      end
 
      private
      def commit(request, endpoint=:default)
        url = URL
        url = THREE_D_SECURE_URL if endpoint == :three_d_secure
        url = RECURRING_PAYMENTS_URL if endpoint == :recurring
        
        response = ssl_post(url, request)
        parsed = parse(response)

        options = {
          :test => parsed[:message] =~ /\[ test system \]/,
          :authorization => parsed[:authcode],
          :cvv_result => parsed[:cvnresult],
          :body => response,
          :avs_result => {
            :street_match => parsed[:avsaddressresponse],
            :postal_match => parsed[:avspostcoderesponse]
          }
        }

        if endpoint == :three_d_secure
          options.merge!({
            :pa_req => parsed[:pareq],
            :acs_url => parsed[:url],
            :three_d_secure => true,
            :xid => parsed[:xid],
            :three_d_secure_enrolled => parsed[:enrolled] == "Y" ? true : false
          })
        end

        Response.new(parsed[:result] == "00", message_from(parsed), parsed, options)
      end
      
      def parse(xml)
        response = {}
                
        xml = REXML::Document.new(xml)
        
        return response unless xml.root

        xml.elements.each('//response/*') do |node|

          if (node.elements.size == 0)
            response[node.name.downcase.to_sym] = normalize(node.text)
          else
            node.elements.each do |childnode|
              name = "#{node.name.downcase}_#{childnode.name.downcase}"
              response[name.to_sym] = normalize(childnode.text)
            end              
          end

        end
        
        response
      end
      
      def build_purchase_or_authorization_request(action, money, credit_card, options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'auth' do
          add_merchant_details(xml, options)
          xml.tag! 'orderid', sanitize_order_id(options[:order_id])
          add_ammount(xml, money, options)
          add_card(xml, credit_card)
          xml.tag! 'autosettle', 'flag' => auto_settle_flag(action)
          add_three_d_secure(xml, options) if options[:three_d_secure_sig]
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], amount(money), (options[:currency] || currency(money)), credit_card.number)
          add_comments(xml, options)
          add_address_and_customer_info(xml, options)
        end
        xml.target!
      end
      
      def build_capture_request(authorization, options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'settle' do
          add_merchant_details(xml, options)
          add_transaction_identifiers(xml, authorization, options)
          add_comments(xml, options)
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], '', '', '')
        end
        xml.target!
      end
      
      def build_credit_request(money, authorization, options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'rebate' do
          add_merchant_details(xml, options)
          add_transaction_identifiers(xml, authorization, options)
          xml.tag! 'amount', amount(money), 'currency' => options[:currency] || currency(money)
          xml.tag! 'refundhash', @options[:refund_hash] if @options[:refund_hash]
          xml.tag! 'autosettle', 'flag' => 1          
          add_comments(xml, options)
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], amount(money), (options[:currency] || currency(money)), '')
        end
        xml.target!
      end
      
      def build_void_request(authorization, options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'void' do
          add_merchant_details(xml, options)
          add_transaction_identifiers(xml, authorization, options)
          add_comments(xml, options)
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], '', '', '')
        end
        xml.target!
      end

      def build_cancel_card_request(creditcard, options = {})
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'card-cancel-card' do
          add_merchant_details(xml, options)
          xml.tag! 'card' do          
            xml.tag! 'ref', options[:payment_method]
            xml.tag! 'payerref', options[:user][:id]
            xml.tag! 'expdate', expiry_date(creditcard)
          end
          # TODO userid . card ref . expiry date
          add_signed_digest(xml, timestamp, @options[:login], options[:user][:id], options[:payment_method])
        end
      end
      
      def build_new_card_request(credit_card, options = {})
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'card-new' do
          add_merchant_details(xml, options)
          xml.tag! 'orderid', sanitize_order_id(options[:order_id])
          xml.tag! 'card' do
            xml.tag! 'ref', options[:payment_method]
            xml.tag! 'payerref', options[:user][:id]
            xml.tag! 'number', credit_card.number
            xml.tag! 'expdate', expiry_date(credit_card)
            xml.tag! 'chname', credit_card.name
            xml.tag! 'type', CARD_MAPPING[card_brand(credit_card).to_s]
            xml.tag! 'issueno', credit_card.issue_number
            xml.tag! 'cvn' do
              xml.tag! 'number', credit_card.verification_value
              xml.tag! 'presind', (options['presind'] || (credit_card.verification_value? ? 1 : nil))
            end
          end
          # timestamp.merchantid.orderid.amount.currency.payerref.chname.(card)number
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], '', '', options[:user][:id], credit_card.name, credit_card.number)
        end
        xml.target!
      end

      def build_new_payee_request(options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'payer-new' do
          add_merchant_details(xml, options)
          xml.tag! 'orderid', sanitize_order_id(options[:order_id])
          xml.tag! 'payer', 'type' => 'Business', 'ref' => options[:user][:id] do
            xml.tag! 'firstname', options[:user][:first_name]
            xml.tag! 'surname', options[:user][:last_name]
          end
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], '', '', options[:user][:id])
        end
        xml.target!
      end

      def build_3d_secure_verify_signature_or_enrolled_request(action, money, credit_card, options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => action do
          add_merchant_details(xml, options)
          xml.tag! 'orderid', sanitize_order_id(options[:order_id])
          add_ammount(xml, money, options)
          add_card(xml, credit_card)
          xml.tag!('pares', options[:three_d_secure_auth][:pa_res]) if(action == '3ds-verifysig' && options[:three_d_secure_auth] )
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], amount(money), (options[:currency] || currency(money)), credit_card.number)
          add_comments(xml, options)
        end
        xml.target!
      end

      def add_three_d_secure(xml, options)
        if options[:three_d_secure_sig]
          xml.tag! 'mpi' do
            xml.tag! 'cavv', options[:three_d_secure_sig][:cavv]
            xml.tag! 'xid', options[:three_d_secure_sig][:xid]
            xml.tag! 'eci', options[:three_d_secure_sig][:eci]
          end
        end
      end
      
      def build_receipt_in_request(money, credit_card, options)
        timestamp = self.class.timestamp
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'request', 'timestamp' => timestamp, 'type' => 'receipt-in' do
          add_merchant_details(xml, options)
          xml.tag! 'orderid', sanitize_order_id(options[:order_id])
          add_ammount(xml, money, options)
          xml.tag! 'payerref', options[:user][:id]
          xml.tag! 'paymentmethod', options[:payment_method]
          xml.tag! 'autosettle', 'flag' => '1'
          add_signed_digest(xml, timestamp, @options[:login], options[:order_id], amount(money), (options[:currency] || currency(money)), options[:user][:id])
          add_comments(xml, options)
          add_address_and_customer_info(xml, options)
        end
        xml.target!
      end
      
      def add_address_and_customer_info(xml, options)
        billing_address = options[:billing_address] || options[:address]
        shipping_address = options[:shipping_address]
        
        return unless billing_address || shipping_address || options[:customer] || options[:invoice] || options[:ip]
        
        xml.tag! 'tssinfo' do
          
          xml.tag! 'custnum', options[:customer] if options[:customer]
          xml.tag! 'prodid', options[:invoice] if options[:invoice]
          xml.tag! 'custipaddress', options[:ip] if options[:ip]
          # xml.tag! 'varref' 
          
          if billing_address
            xml.tag! 'address', 'type' => 'billing' do
              xml.tag! 'code', avs_input_code_or_zip( billing_address, options )
              xml.tag! 'country', billing_address[:country]
            end
          end
          
          if shipping_address
            xml.tag! 'address', 'type' => 'shipping' do
              xml.tag! 'code', shipping_address[:zip]
              xml.tag! 'country', shipping_address[:country]
            end
          end
          
        end
      end
      
      def avs_input_code_or_zip(address, options)
        options[ :skip_avs_check ] ? address[ :zip ] : avs_input_code( address )
      end
      
      def add_merchant_details(xml, options)
        xml.tag! 'merchantid', @options[:login] 
        if options[:account] || @options[:account]
          xml.tag! 'account', options[:account] || @options[:account]
        end
      end
      
      def add_transaction_identifiers(xml, authorization, options)
        xml.tag! 'orderid', sanitize_order_id(options[:order_id])
        xml.tag! 'pasref', options[:pasref]
        xml.tag! 'authcode', authorization
      end
      
      def add_comments(xml, options)
        return unless options[:description]
        xml.tag! 'comments' do
          xml.tag! 'comment', options[:description], 'id' => 1 
        end
      end
      
      def add_ammount(xml, money, options)
        xml.tag! 'amount', amount(money), 'currency' => options[:currency] || currency(money)
      end
      
      def add_card(xml, credit_card)
        xml.tag! 'card' do
          xml.tag! 'number', credit_card.number
          xml.tag! 'expdate', expiry_date(credit_card)
          xml.tag! 'chname', credit_card.name
          xml.tag! 'type', CARD_MAPPING[card_brand(credit_card).to_s]
          xml.tag! 'issueno', credit_card.issue_number
          xml.tag! 'cvn' do
            xml.tag! 'number', credit_card.verification_value
            xml.tag! 'presind', (options['presind'] || (credit_card.verification_value? ? 1 : nil))
          end
        end
      end

      def avs_input_code(address)
        address.values_at(:zip, :address1).map{ |v| extract_digits(v) }.join('|')
      end

      def extract_digits(string)
        return "" if string.nil?
        string.gsub(/[\D]/,'')
      end

      def stringify_values(values)
        string = ""
        values.each do |val|
          string << "#{val}"
          string << "." unless val.equal?(values.last)
        end
        string
      end
      
      def add_signed_digest(xml, *values)
        string = stringify_values(values)
        xml.tag! 'sha1hash', sha1from(string)
      end
      
      def auto_settle_flag(action)
        action == :authorization ? '0' : '1'
      end
      
      def expiry_date(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :two_digits)}"
      end
      
      def sha1from(string)
        Digest::SHA1.hexdigest("#{Digest::SHA1.hexdigest(string)}.#{@options[:password]}")
      end
      
      def normalize(field)
        case field
        when "true"   then true
        when "false"  then false
        when ""       then nil
        when "null"   then nil
        else field
        end        
      end

      def message_from(response)
        message = nil
        case response[:result]                
        when "00"
          message = SUCCESS
        when "101"
          message = response[:message]
        when "102", "103"
          message = DECLINED
        when /^2[0-9][0-9]/
          message = BANK_ERROR
        when /^3[0-9][0-9]/
          message = REALEX_ERROR
        when /^5[0-9][0-9]/
          message = response[:message]
        when "600", "601", "603"
          message = ERROR
        when "666"
          message = CLIENT_DEACTIVATED
        else
          message = DECLINED
        end  
      end
      
      def sanitize_order_id(order_id)
        order_id.to_s.gsub(/[^a-zA-Z0-9\-_]/, '')
      end
      
      def self.timestamp
        Time.now.strftime('%Y%m%d%H%M%S')
      end
    end
  end
end
