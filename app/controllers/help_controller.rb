class HelpController < ApplicationController

  # GET /help/doc_html
  def doc_html
    doc = File.read(Rails.root.join('doc/trixx.html'))
    render html: doc.html_safe
  rescue Exception => e
    render html: "#{e.message}"
  end

  # GET /help/doc_pdf
  def doc_pdf
    doc = File.read(Rails.root.join('doc/trixx.pdf'))
    render pdf: doc.html_safe
  rescue Exception => e
    render html: "#{e.message}"
  end

  private
end
