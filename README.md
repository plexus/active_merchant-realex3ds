Realex 3D Secure Gateway for ActiveMerchant
===========================================

The Gateway included in ActiveMerchant does not support 3D Secure. This implementation was done by David Rice and sponsored by [Ticketsolve](http://ticketsolve.com).

In your Gemfile

```ruby
gem 'activemerchant-realex3ds'
```

In your code

```ruby
require 'active_merchant'
require 'active_merchant/billing/gateways/realex3ds'

gateway = ActiveMerchant::Billing::Realex3dsGateway.new(
            :login => 'TestMerchant',
            :password => 'password')
```

See [ActiveMerchant](http://github.com/Shopify/active_merchant) for more details.

Ported to current version of ActiveMerchant and extracted into a Gem by Arne Brasseur.
