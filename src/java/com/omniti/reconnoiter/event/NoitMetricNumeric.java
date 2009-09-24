/*
 * Copyright (c) 2009, OmniTI Computer Consulting, Inc.
 * All rights reserved.
 * The software in this package is published under the terms of the GPL license
 * a copy of which can be found at:
 * https://labs.omniti.com/reconnoiter/trunk/src/java/LICENSE
 */

package com.omniti.reconnoiter.event;

import com.omniti.reconnoiter.StratconMessage;

public class NoitMetricNumeric extends StratconMessage {
    private String uuid;
    private String name;
    private Double value;
    private String noit;

  protected String getPrefix() {
     return "M";
   }
   /*
   'M' REMOTE TIMESTAMP UUID NAME TYPE VALUE
    */
   public NoitMetricNumeric(String[] parts) throws Exception {
      super(parts);
      noit = parts[1];
      uuid = parts[3];
      name = parts[4];
      try {
        value = Double.valueOf(parts[6]);
      } catch (NumberFormatException nfe) {
        value = null;
      }

   }

    public String getUuid() { return uuid; }
    public String getName() { return name; }
    public Double getValue() { return value; }
    public String getNoit() { return noit; }

  protected int getLength() {
     return 7;
   }
}
