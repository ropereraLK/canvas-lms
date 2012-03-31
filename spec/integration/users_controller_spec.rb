#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe UsersController do
  describe "#teacher_activity" do
    before do
      course_with_teacher_logged_in(:active_all => true)
      @course.update_attribute(:name, 'coursename1')
      @enrollment.update_attribute(:limit_privileges_to_course_section, true)
      @et = @enrollment
      @s1 = @course.course_sections.first
      @s2 = @course.course_sections.create!(:name => 'Section B')
      @e1 = student_in_course(:active_all => true)
      @e2 = student_in_course(:active_all => true)
      @e1.user.update_attribute(:name, 'studentname1')
      @e2.user.update_attribute(:name, 'studentname2')
      @e2.update_attribute(:course_section, @s2)
    end

    it "should count conversations as interaction" do
      get user_student_teacher_activity_url(@teacher, @e1.user)
      Nokogiri::HTML(response.body).at_css('table.report tr:first td:nth(2)').text.should match(/never/)

      @conversation = Conversation.initiate([@e1.user_id, @teacher.id], false)
      @conversation.add_message(@teacher, "hello")

      get user_student_teacher_activity_url(@teacher, @e1.user)
      Nokogiri::HTML(response.body).at_css('table.report tr:first td:nth(2)').text.should match(/less than 1 day/)
    end

    it "should only include students the teacher can view" do
      get user_course_teacher_activity_url(@teacher, @course)
      response.should be_success
      response.body.should match(/studentname1/)
      response.body.should_not match(/studentname2/)
    end

    it "should show user notes if enabled" do
      get user_course_teacher_activity_url(@teacher, @course)
      response.body.should_not match(/journal entry/i)
      @course.root_account.update_attribute(:enable_user_notes, true)
      get user_course_teacher_activity_url(@teacher, @course)
      response.body.should match(/journal entry/i)
    end

    it "should show individual user info across courses" do
      @course1 = @course
      @course2 = course(:active_course => true)
      @course2.update_attribute(:name, 'coursename2')
      student_in_course(:course => @course2, :user => @e1.user)
      get user_student_teacher_activity_url(@teacher, @e1.user)
      response.should be_success
      response.body.should match(/studentname1/)
      response.body.should_not match(/studentname2/)
      response.body.should match(/coursename1/)
      # teacher not in course2
      response.body.should_not match(/coursename2/)
      # now put teacher in course2
      @course2.enroll_teacher(@teacher).accept!
      get user_student_teacher_activity_url(@teacher, @e1.user)
      response.should be_success
      response.body.should match(/coursename1/)
      response.body.should match(/coursename2/)
    end

    it "should be available for concluded courses/enrollments" do
      account_admin_user(:username => "admin")
      user_session(@admin)

      @course.complete
      @et.conclude
      @e1.conclude

      get user_student_teacher_activity_url(@teacher, @e1.user)
      response.should be_success
      response.body.should match(/studentname1/)

      get user_course_teacher_activity_url(@teacher, @course)
      response.should be_success
      response.body.should match(/studentname1/)
    end

    it "should show concluded students to active teachers" do
      @e1.conclude

      get user_student_teacher_activity_url(@teacher, @e1.user)
      response.should be_success
      response.body.should match(/studentname1/)

      get user_course_teacher_activity_url(@teacher, @course)
      response.should be_success
      response.body.should match(/studentname1/)
    end
  end

  describe "#index" do
    it "should render" do
      user_with_pseudonym(:active_all => 1)
      @johnstclair = @user.update_attributes(:name => 'John St. Clair', :sortable_name => 'St. Clair, John')
      user_with_pseudonym(:active_all => 1, :username => 'jtolds@instructure.com', :name => 'JT Olds')
      @jtolds = @user
      Account.default.add_user(@user)
      user_session(@user, @pseudonym)
      get account_users_url(Account.default)
      response.should be_success
      response.body.should match /Olds, JT.*St\. Clair, John/m
    end
  end

  describe "#avatar_image_url" do
    before do
      course_with_student_logged_in(:active_all => true)
      @a = Account.default
      enable_avatars!
    end

    def enable_avatars!
      @a.enable_service(:avatars)
      @a.save!
    end

    def disable_avatars!
      @a.disable_service(:avatars)
      @a.save!
    end

    it "should maintain protocol and domain name in fallback" do
      disable_avatars!
      enable_cache do
        get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
        response.should redirect_to "http://someschool.instructure.com/images/no_pic.gif"

        get "https://otherschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
        response.should redirect_to "https://otherschool.instructure.com/images/no_pic.gif"
      end
    end

    it "should maintain protocol and domain name in gravatar redirect fallback" do
      enable_cache do
        get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("http://someschool.instructure.com/images/no_pic.gif")}"

        get "https://otherschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("https://otherschool.instructure.com/images/no_pic.gif")}"
      end
    end

    it "should return different urls for different fallbacks" do
      enable_cache do
        get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("http://someschool.instructure.com/images/no_pic.gif")}"

        get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}?fallback=#{CGI.escape("/my/custom/fallback/url.png")}"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("http://someschool.instructure.com/my/custom/fallback/url.png")}"

        get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}?fallback=#{CGI.escape("https://test.domain/another/custom/fallback/url.png")}"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("https://test.domain/another/custom/fallback/url.png")}"
      end
    end

    it "should forget all cached urls when the avatar changes" do
      enable_cache do
        data = Rails.cache.instance_variable_get(:@data)
        orig_size = data.size

        get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("http://someschool.instructure.com/images/no_pic.gif")}"

        get "https://otherschool.instructure.com/images/users/#{User.avatar_key(@user.id)}?fallback=/my/custom/fallback/url.png"
        response.should redirect_to "https://secure.gravatar.com/avatar/000?s=50&d=#{CGI::escape("https://otherschool.instructure.com/my/custom/fallback/url.png")}"

        diff = data.select{|k,v|k =~ /avatar_img/}.size - orig_size
        diff.should > 0

        expect {
          @user.update_attribute(:avatar_image, {'type' => 'attachment', 'url' => '/images/thumbnails/foo.gif'})
        }.to change(data, :size).by(-diff)

        expect {
          get "http://someschool.instructure.com/images/users/#{User.avatar_key(@user.id)}"
          response.should redirect_to "http://someschool.instructure.com/images/thumbnails/foo.gif"

          get "http://otherschool.instructure.com/images/users/#{User.avatar_key(@user.id)}?fallback=#{CGI::escape("https://test.domain/my/custom/fallback/url.png")}"
          response.should redirect_to "http://otherschool.instructure.com/images/thumbnails/foo.gif"
        }.to change(data, :size).by(diff)
      end
    end
  end
end

