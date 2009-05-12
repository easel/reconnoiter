package com.omniti.reconnoiter.event;

import java.lang.System;

import com.omniti.reconnoiter.StratconMessage;
import com.espertech.esper.client.EPStatement;
import com.espertech.esper.client.UpdateListener;
import java.util.UUID;
import javax.xml.xpath.XPath;
import javax.xml.xpath.XPathFactory;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathExpressionException;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

public class StratconQuery extends StratconMessage {
  private EPStatement statement;
  private UpdateListener listener;
  private UUID uuid;
  private String name;
  private String expression;

  public StratconQuery(Document d) {
    XPath xpath = XPathFactory.newInstance().newXPath();
    try {
      String id = (String) xpath.evaluate("/StratconQuery/id", d, XPathConstants.STRING);
      if(id == null) uuid = UUID.randomUUID();
      else uuid = UUID.fromString(id);
      name = (String) xpath.evaluate("/StratconQuery/name", d, XPathConstants.STRING);
      expression = (String) xpath.evaluate("/StratconQuery/expression", d, XPathConstants.STRING);
    }
    catch(XPathExpressionException e) {
    }
    if(name == null) name = "default";
    if(uuid == null) uuid = UUID.randomUUID();
System.err.println("In StratconQuery Constructor Name: " + name);
System.err.println("In StratconQuery Constructor id: " + uuid);
System.err.println("In StratconQuery Constructor expression: " + expression);
  }
  public UUID getUUID() {
    return uuid;
  }
  public String getExpression() {
    return expression;
  }
  public String getName() {
    return name;
  }
  public void setStatement(EPStatement s) {
    this.statement = s;
  }
  public void setListener(UpdateListener l) {
    this.listener = l;
  }
  public void destroy() {
    statement.removeListener(listener);
    statement.destroy();
  }
}
