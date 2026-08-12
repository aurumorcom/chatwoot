class Contacts::UpsertService
  pattr_initialize [:account!, :params!, :user]

  def perform
    contact = find_existing_contact
    if contact
      update_contact(contact)
    else
      create_contact
    end
  rescue ActiveRecord::RecordNotUnique
    contact = find_existing_contact
    contact ? update_contact(contact) : raise
  end

  private

  def find_existing_contact
    if params[:identifier].present?
      contact = account.contacts.find_by(identifier: params[:identifier])
      return contact if contact.present?
    end

    if params[:email].present?
      contact = account.contacts.find_by(email: params[:email].to_s.strip.downcase)
      return contact if contact.present?
    end

    if params[:phone_number].present?
      contact = account.contacts.find_by(phone_number: params[:phone_number].to_s.strip)
      return contact if contact.present?
    end

    if params[:q].present?
      account.contacts.where(
        'name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR contacts.identifier LIKE :search',
        search: "%#{params[:q].strip}%"
      ).first
    end
  end

  def update_contact(contact)
    contact.assign_attributes(contact_params)
    contact.save!
    process_avatar_from_url(contact) if params[:avatar_url].present?
    contact
  end

  def create_contact
    contact = account.contacts.create!(contact_params)
    process_avatar_from_url(contact) if params[:avatar_url].present?
    contact
  end

  def contact_params
    allowed = [:name, :email, :phone_number, :identifier, :company_id, :middle_name, :last_name,
               :city, :country_code, custom_attributes: {}, additional_attributes: {}]
    params.permit(*allowed)
  end

  def process_avatar_from_url(contact)
    Avatar::AvatarFromUrlJob.perform_later(contact, params[:avatar_url])
  end
end
