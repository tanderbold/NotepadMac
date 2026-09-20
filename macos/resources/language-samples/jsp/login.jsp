<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page errorPage="error.jsp" %>
<%!
    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }
%>
<%
    String user = request.getParameter("user");
    String message = null;
    if ("POST".equalsIgnoreCase(request.getMethod())) {
        if (isBlank(user)) {
            message = "Please enter your user name.";
        } else {
            session.setAttribute("user", user);
            response.sendRedirect("home.jsp");
            return;
        }
    }
%>
<html>
<body>
<form method="post" action="login.jsp">
    <label for="user">User</label>
    <input type="text" id="user" name="user" value="<%= user == null ? "" : user %>">
    <input type="password" name="password">
    <button type="submit">Sign in</button>
</form>
<% if (message != null) { %>
    <p class="error"><%= message %></p>
<% } %>
</body>
</html>
