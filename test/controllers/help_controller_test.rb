require 'test_helper'

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "should get doc_html" do
    FileUtils.cp Rails.root.join('test/fixtures/files/trixx.html.testfile'), Rails.root.join('doc/trixx.html')
    get "/help/doc_html", as: :html
    assert_response :success
  end

  test "should get doc_pdf" do
    FileUtils.cp Rails.root.join('test/fixtures/files/trixx.pdf.testfile'), Rails.root.join('doc/trixx.pdf')
    get "/help/doc_pdf", as: :html
    assert_response :success
  end

end
