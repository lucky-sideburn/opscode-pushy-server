
require 'spec_helper'

describe Pushy::Client do
  include SpecHelpers::Config

  let(:metadata) { self.class.metadata }
  let(:server) { metadata[:server] || (metadata[:server] = TinyServer::Manager.new) }
  let(:api) { TinyServer::API.instance.tap(&:clear) }
  let(:config_endpoint) { api.get '/config.json', 200, StringIO.new(config_json) }

  before(:each) { server.start }
  after(:each) { server.stop }

  # FIXME: Something is borked here when this is enabled.
  pending '.load!' do
    subject { given; Pushy::Client.load! }
    let(:given) { config_endpoint }

    it { should_not be_nil }
  end

  context 'with configuration endpoint' do
    let(:given) { config_endpoint }
    let(:pushy_client) { given; Pushy::Client.load! }

    def self.its(_attribute, &expectation)
      context "with configuration attribute :#{_attribute}" do
        subject { pushy_client.send(_attribute) }
        it('should set attribute', &expectation)
      end
    end

    its(:node_name)   { should eql host }
    its(:in_address)  { should eql in_addr }
    its(:out_address) { should eql out_addr }
    its(:interval)    { should eql interval }

    its(:offline_threshold) { should eql offline_threshold }
    its(:online_threshold)  { should eql online_threshold }
    its(:lifetime)          { should eql lifetime }

    its(:server_public_key)  { should eql public_key }
  end
end