<%@ taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core" %>
<%@ taglib prefix="fn" uri="http://java.sun.com/jsp/jstl/functions" %>
<jsp:useBean id="cart" class="com.example.shop.Cart" scope="session"/>
<div class="header">
    <a href="<c:url value='/index.jsp'/>">Home</a>
    <c:if test="${not empty sessionScope.user}">
        Welcome, <c:out value="${sessionScope.user}"/>
        (<a href="<c:url value='/logout'/>">log out</a>)
    </c:if>
    <span class="cart">Cart: ${fn:length(cart.items)} item(s)</span>
    <jsp:getProperty name="cart" property="total"/>
</div>
