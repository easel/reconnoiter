/*
 * Copyright (c) 2009, OmniTI Computer Consulting, Inc.
 * All rights reserved.
 * The software in this package is published under the terms of the GPL license
 * a copy of which can be found at:
 * https://labs.omniti.com/reconnoiter/trunk/src/java/LICENSE
 */

package com.omniti.reconnoiter.event;


import com.omniti.reconnoiter.event.StratconQueryBase;
import com.espertech.esper.client.UpdateListener;
import java.util.UUID;

public class StratconQuery extends StratconQueryBase {
  protected UpdateListener listener;
  protected String name;

  protected String getPrefix() {
     return "Q";
   }

  /*  'Q' REMOTE ID NAME QUERY  */
  public StratconQuery(String[] parts) throws Exception {
    super(parts);
    String id = parts[2];
    name = parts[3];
    expression = parts[4];
    if(id == null)
      uuid = UUID.randomUUID();
    else
      uuid = UUID.fromString(id);

    if(name == null) name = "default";
    if(uuid == null) uuid = UUID.randomUUID();
  }
  public String getName() {
    return name;
  }
  public void setListener(UpdateListener l) {
    this.listener = l;
  }
  public void destroy() {
    statement.removeListener(listener);
    statement.destroy();
  }

  protected int getLength() {
    return 5;
  }
}
