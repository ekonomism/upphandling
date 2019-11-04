require 'rubygems'
require 'sinatra'

set :sessions => true

register do
  def auth(user)
    condition do
      redirect "/auth" unless session[:inloggad] == true
    end
  end
end

before do
  @user = session[:inloggad]
end

get "/auth" do
  erb :signin
end

post "/login" do
  if params[:password] == "password" then
    session[:inloggad] = true
    redirect "/"
  else
    @fel = true
    redirect "/auth"
  end  
end

get "/logout" do
  session[:inloggad] = false
end

get "/", :auth => :true do
  
end
