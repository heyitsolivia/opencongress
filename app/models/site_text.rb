# == Schema Information
#
# Table name: site_texts
#
#  id         :integer          not null, primary key
#  text_type  :string(255)
#  text       :text
#  updated_at :datetime
#

class SiteText < OpenCongressModel
  def self.find_by_type(text_type)
    st = self.where('text_type = ?',text_type).first
    st ? st.text : nil
  end
  
  def self.find_title_desc(tag)
    self.find_by_type("#{tag}:title_desc")
  end

  def self.find_dropdown_text(tag)
    self.find_by_type("#{tag}:dropdown_text")
  end
  
  def self.find_explain(tag)
    self.find_by_type("#{tag}:explain")
  end

  def self.find_plaintext(tag)
    self.find_by_type("#{tag}:plaintext")
  end
end
