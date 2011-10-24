# encoding: utf-8
# author: Boris Barroso
# email: boriscyber@gmail.com
class User < ActiveRecord::Base

  has_secure_password
  include Models::User::Authentication

  # callbacks
  before_validation :set_rolname, :if => :new_record?
  before_create     :create_user_link, :if => :change_default_password?
  before_destroy    :destroy_links
  
  ABBREV = "GEREN"
  ROLES = ['admin', 'gerency', 'operations']

  attr_accessor :temp_password, :rolname, :active_link, :old_password#, :abbreviation

  # Relationships
  has_many :links, :autosave => true, :dependent => :destroy
  has_many :organisations, :through => :links

  # Validations
  validates_presence_of :email
  validates_length_of :abbreviation, :minimum => 2, :on => :create
  validates :email, :format => {
    :with => /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i, 
    :message => I18n.t("errors.messages.user.email")
  }

  with_options :if => :new_record? do |u|
    u.validates_inclusion_of :rolname, :in => ROLES
    u.validates :password, :length => {:minimum => 6}
  end

  #with_options :if => :change_default_password? do |u|
  #  u.validates_inclusion_of :rolname, :in => ROLES.slice(1,3)
  #end

  #attr_protected :account_type
  attr_accessible :email, :password, :password_confirmation, :first_name, :last_name, :phone, :mobile, :website, 
    :description, :rolname, :address, :abbreviation, :old_password

  def to_s
    unless first_name.blank? and last_name.blank?
      %Q(#{first_name} #{last_name})
    else
      %Q(#{email})
    end
  end

  # Returns the link with te organissation one is logged in
  def link
    @link ||= links.find_by_organisation_id(OrganisationSession.organisation_id)
  end

  # Methods for a defined link
  [:rol, :active].each do |met|
    class_eval <<-CODE, __FILE__, __LINE__ + 1
      def link_#{met}
        link.#{met}
      end
    CODE
  end

  # returns the organisation which one is logged in
  def organisation
    Organisation.find(OrganisationSession.organisation_id)
  end

  def rol
    link.rol
  end

  def self.admin_gerency?(val)
    ROLES.slice(0, 2).include? val
  end

  # Checks the user and the priviledges
  def check_organisation?(organisation_id)
    organisations.map(&:id).include?(organisation_id.to_i)
  end

  def update_default_password(params)
    pwd, pwd_conf = params[:password], params[:password_confirmation]

    unless pwd == pwd_conf
      self.errors[:password] << I18n.t("errors.messages.user.password_confirmation")
      return false
    end
    self.change_default_password = false
    self.password = pwd

    self.save
  end

  def update_password(params)
    return false if change_default_password?

    unless authenticate(params[:old_password])
      self.errors[:old_password] << I18n.t("errors.messages.user.wrong_password")
      return false
    end

    unless params[:password] === params[:password_confirmation]
      self.errors[:password] << I18n.t("errors.messages.user.password_confirmation")
      return false
    end

    self.password = params[:password]

    self.save
  end

  # Adds a new user for the company
  def add_company_user(params)
    self.attributes = params
    self.email = params[:email]

    set_random_password
    self.change_default_password = true

    self.save
  end

  # Updates the priviledges of a user
  def update_user_role(params)
    self.link.update_attributes(:rol => params[:rolname], :active => params[:active_link])
  end

  # returns translated roles
  def self.get_roles
    ["Genrencia", "Administración", "Operaciones"].zip(ROLES)
  end

  def self.roles_hash
    Hash[ROLES.zip(["Genrencia", "Administración", "Operaciones"])]
  end

  def self.new_user(email, password)
    User.new(:password => password ) {|u| 
      u.email = email 
      u.abbreviation = ABBREV
    }
  end

  def update_user_attributes(params)
    self.attributes = params[:user]
    lnk = links.select {|v| v.organisation_id = OrganisationSession.organisation_id}.first
    rol = params[:rolname]
    rol = ROLES[1,2].last unless ROLES[1,2].include?(rol)

    lnk.rol = rol

    self.save
  end

  protected
  # Generates a random password and sets it to the password field
  def set_random_password(size = 8)
    self.password = self.temp_password = SecureRandom.urlsafe_base64(size)
  end


  private
  def create_user_link
    links.build(:organisation_id => OrganisationSession.organisation_id, 
                    :rol => rolname, :creator => false) {|link| 
      link.abbreviation = abbreviation 
    }
  end

  def destroy_links
    links.destroy_all
  end

  def set_rolname
    unless change_default_password?
      self.rolname = 'admin'
    end
  end

end
