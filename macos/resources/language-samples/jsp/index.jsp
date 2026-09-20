<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="java.util.List, com.example.shop.Product" %>
<%@ taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core" %>
<%@ taglib prefix="fmt" uri="http://java.sun.com/jsp/jstl/fmt" %>
<!DOCTYPE html>
<html>
<head>
    <title>${pageTitle}</title>
    <link rel="stylesheet" href="${pageContext.request.contextPath}/css/shop.css">
</head>
<body>
<jsp:include page="/WEB-INF/fragments/header.jsp"/>
<h1>Products</h1>
<c:choose>
    <c:when test="${empty products}">
        <p>No products found.</p>
    </c:when>
    <c:otherwise>
        <table>
            <c:forEach var="p" items="${products}" varStatus="row">
                <tr class="${row.index % 2 == 0 ? 'even' : 'odd'}">
                    <td><c:out value="${p.name}"/></td>
                    <td><fmt:formatNumber value="${p.price}" type="currency"/></td>
                </tr>
            </c:forEach>
        </table>
    </c:otherwise>
</c:choose>
<%
    Integer visits = (Integer) session.getAttribute("visits");
    visits = visits == null ? 1 : visits + 1;
    session.setAttribute("visits", visits);
%>
<p>You have visited <%= visits %> times.</p>
</body>
</html>
