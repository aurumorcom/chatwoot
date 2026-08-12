require 'rails_helper'

RSpec.describe Contacts::UpsertService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '#perform' do
    context 'when contact does not exist' do
      it 'creates a new contact' do
        params = ActionController::Parameters.new(
          name: 'John Doe',
          email: 'john@example.com',
          phone_number: '+1234567890',
          identifier: 'id_123'
        )

        expect do
          described_class.new(account: account, params: params, user: user).perform
        end.to change(account.contacts, :count).by(1)

        contact = account.contacts.last
        expect(contact.name).to eq('John Doe')
        expect(contact.email).to eq('john@example.com')
        expect(contact.identifier).to eq('id_123')
      end
    end

    context 'when matching by identifier' do
      let!(:existing) { create(:contact, account: account, identifier: 'id_123', name: 'Old Name') }

      it 'updates existing contact matching identifier' do
        params = ActionController::Parameters.new(
          identifier: 'id_123',
          name: 'Updated Name',
          email: 'newemail@example.com'
        )

        contact = described_class.new(account: account, params: params, user: user).perform
        expect(contact.id).to eq(existing.id)
        expect(contact.reload.name).to eq('Updated Name')
        expect(contact.email).to eq('newemail@example.com')
      end
    end

    context 'when matching by email' do
      let!(:existing) { create(:contact, account: account, email: 'john@example.com', name: 'Old Name') }

      it 'updates existing contact matching email' do
        params = ActionController::Parameters.new(
          email: 'john@example.com',
          name: 'Updated Name'
        )

        contact = described_class.new(account: account, params: params, user: user).perform
        expect(contact.id).to eq(existing.id)
        expect(contact.reload.name).to eq('Updated Name')
      end
    end

    context 'when matching by phone_number' do
      let!(:existing) { create(:contact, account: account, phone_number: '+1234567890', name: 'Old Name') }

      it 'updates existing contact matching phone_number' do
        params = ActionController::Parameters.new(
          phone_number: '+1234567890',
          name: 'Updated Name'
        )

        contact = described_class.new(account: account, params: params, user: user).perform
        expect(contact.id).to eq(existing.id)
        expect(contact.reload.name).to eq('Updated Name')
      end
    end
  end
end
