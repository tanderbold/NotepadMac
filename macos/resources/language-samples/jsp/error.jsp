<%@ page isErrorPage="true" contentType="text/html;charset=UTF-8" %>
<%@ page import="java.io.PrintWriter, java.io.StringWriter" %>
<html>
<head><title>Something went wrong</title></head>
<body>
<h2>Error <%= response.getStatus() %></h2>
<p><%= exception != null ? exception.getMessage() : "Unknown error" %></p>
<%
    if (exception != null && request.getParameter("debug") != null) {
        StringWriter sw = new StringWriter();
        exception.printStackTrace(new PrintWriter(sw));
        out.println("<pre>" + sw + "</pre>");
    }
%>
<jsp:forward page="/WEB-INF/fragments/footer.jsp">
    <jsp:param name="from" value="error"/>
</jsp:forward>
</body>
</html>
