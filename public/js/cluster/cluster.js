var i = 0,
    sduration = 250,
    duration = 1000,
    root,
    defaultStroke = 3.5,
    fontSize = 10,
    lineSpace = 2,
    boxHeight = 50,
    boxWidth = 85,
    width = 625,
    height = 1000;

var yscale_performancebar = d3.scale.linear()
  .domain([0, 1])
  .rangeRound([boxHeight/2, -boxHeight/2]);

var cluster = d3.layout.cluster().size([height, width -160]);
var tree = d3.layout.tree().size([height, width -160]);

var diagonal = d3.svg.diagonal()
  .projection(function(d) { return [d.y, d.x]; });

var svg = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height)
    .append("g")
    .attr("transform", "translate(80, 0)");

var divpopup = d3.select("body").append("div")
    .attr("id", "popup")
    .style("position", "absolute")
    .style("color", "white")
    .style("font-size", "14px")
    .style("background", "rgba(0,0,0,0.5)")
    .style("padding", "5px 10px 5px 10px")
    .style("-moz-border-radius", "5px 5px")
    .style("border-radius", "5px 5px")
    .style("z-index", "10")
    .style("visibility", "hidden");

divpopup.append("div")
    .attr("id", "popup-title")
    .style("font-size", "15px")
    .style("width", "200px")
    .style("margin-bottom", "4px")
    .style("font-weight", "bolder");

divpopup.append("div")
    .attr("id", "popup-content")
    .style("font-size", "12px");

divpopup.append("div")
    .attr("id", "popup-desc")
    .style("font-size", "14px");

var url = "cluster.json"
// var url = "http://localhost:4567/cluster.json"
// var url = "cluster.json"

d3.json(url, function(error, json) {

  root = json;
  root.x0 = height / 2;
  root.y0 = 0;

  function collapse(d) {
    if (d.children) {
      d._children = d.children;
      d._children.forEach(collapse);
      d.children = null;
    }
  }

  root.children.forEach(collapse);
  update(root);
})

function update(source) {

  var nodes = tree.nodes(root).reverse(),
    links = tree.links(nodes);

  nodes.forEach(function(d) { d.y = d.depth * 180; });

  var node = svg.selectAll("g.node")
    .data(nodes, function(d) { return d.id || (d.id = ++i); });

  var nodeEnter = node.enter().append("g")
    .attr("class", "node")
    .attr("transform", function(d) { return "translate(" + source.y0 + "," + source.x0 + ")"; })
    .on("click", nodeClick)
    .on("mouseover", function(d) {
      divpopup.selectAll("#popup-content").text("node id: " + d.node_id + ", " + "execution id: " + d.execution_id + ", " + "address: " + d.address);
      divpopup.selectAll("#popup-desc").text("parallel: " + d.parallel + ", " + "queueing: " + d.queueing + ", " + "executing: " + d.executing + ", " + "state: " + d.state);

      divpopup
        .style("visibility", "visible");
    })
    .on("mousemove", function(d) {
      // divpopup.style("top", (event.pageY - 50) + "px")
      //   .style("left", (event.pageX + 10) + "px");
      // console.log(event);
      divpopup.style("left", (event.clientX + 10) + "px")
          .style("top", (event.clientY - 50) + "px");
    })
    .on("mouseout", function(d) {
      divpopup
        .style("visibility", "hidden");
    });

  nodeEnter.append("rect")
    .attr('class', 'nodebox')
    .attr("x", -boxWidth/2)
    .attr("y", -boxHeight/2)
    .attr("width", boxWidth)
    .attr("height", boxHeight)
    .style("stroke", function(d) {
      return getTypeColor(d);
    });

  nodeEnter.append("rect")
    .attr('id', 'performancebar')
    .attr("x", boxWidth/2*1.05)
    .attr("width", boxWidth/10)
    .style("fill", "red")
    .style("stroke", "red")
    .attr("y", boxHeight/2)
    .attr("height", 0);

  nodeEnter.append("text")
    .attr("id", "nodetitle")
    .attr("class", "nodeTitle")
    .attr("y", -boxHeight/2 + fontSize + 2*lineSpace)
    .attr("text-anchor", "middle")
    .text(function(d) { return d.node_type + ":" + d.node_id; });

  nodeEnter.append("text")
    .attr("text-anchor", "middle")
    .attr("class", "nodeText")
    .attr("id", "nodeDescription")
    .attr("y", -boxHeight/2 + 2*fontSize + 3*lineSpace)
    .text(function(d) { return d.address });

  nodeEnter.append("text")
    .attr("text-anchor", "start")
    .attr("class", "nodeText")
    .attr("id", "nodeDetails1")
    .attr("x", -boxWidth/2)
    .attr("y", -boxHeight/2 - 2 * fontSize - 4*lineSpace)

  nodeEnter.append("text")
    .attr("text-anchor", "start")
    .attr("class", "nodeText")
    .attr("id", "nodeDetails2")
    .attr("x", -boxWidth/2)
    .attr("y", -boxHeight/2 - fontSize - 2*lineSpace)

  nodeEnter.select('#performancebar')
    .transition()
    .duration(duration)
    .attr("y", function(d) { return getPerformance(d); })
    .attr("height", function(d) {
      return boxHeight/2 - getPerformance(d);
   });

  var nodeUpdate = node.transition()
    .duration(duration)
    .attr("transform", function(d) { return "translate(" + d.y + "," + d.x + ")"; });

  var nodeExit = node.exit().transition()
    .duration(duration)
    .attr("transform", function(d) { return "translate(" + source.y + "," + source.x + ")"; })
    .remove();

  // nodeExit.select("rect")
    // .attr('class', 'nodebox')
    // .attr("x", -boxWidth/2)
    // .attr("y", -boxHeight/2)
    // .attr("width", boxWidth)
    // .attr("height", boxHeight);

  // update the links
  var link = svg.selectAll("path.link")
    .data(links, function(d) { return d.target.id; });

  link.enter().insert("path", "g")
    .attr("class", "link")
    .attr("d", function(d) {
      var o = {x: source.x0, y: source.y0};
      return diagonal({source: o, target: o});
    });

  link.transition()
    .duration(duration)
    .attr("d", diagonal);

  link.exit().transition()
    .duration(duration)
    .attr("d", function(d) {
      var o = {x: source.x, y: source.y};
      return diagonal({source: o, target: o});
    })
    .remove();

  nodes.forEach(function(d) {
    d.x0 = d.x;
    d.y0 = d.y;
  });
}

// Format f1score message
function node1Text(d) {
    var f1Score = d.params["f1-score"]
    return "f1-Score: " + d3.format("0.1f")(f1Score*100) + "%"
}

function getLinkWidthTotal(node) {
    //return 5E-3*d.target.params.nKPsForThisNode
    return 5E-3*d.target.size;

}

function getLinkWidthClass(node) {
    var className = thisNode.attr("id");
    return node.target.executing / root.executing * boxHeight;
}

function nodeClick(d) {
  if (d.children) {
    d._children = d.children;
    d.children = null;
  } else {
    d.children = d._children;
    d._children = null;
  }
  update(d);
}

// not used
// Highlight node when we mouse-over
function nodeMouseOver(d) {
  thisNode = d3.select(this);
  thisNodeCol = thisNode.select(".nodebox").style("stroke");
  thisNode.selectAll(".nodebox")
    .transition()
    .duration(sduration)
    // .style("opacity", 0.6)
    .style("fill", thisNodeCol);
  svg.selectAll(".link")
    .transition()
    .duration(sduration)
    .style("stroke", thisNodeCol)
    .style("stroke-width",  getLinkWidthClass);
  // show details
  thisNode.select('#nodeDetails1')
    .text(function(d) { return "node id: " + d.node_id + ", " +
                               "execution id: " + d.execution_id + ", " +
                               "address: " + d.address; });

  thisNode.select('#nodeDetails2')
    .text(function(d) { return "parallel: " + d.parallel + ", " +
                               "queueing: " + d.queueing + ", " +
                               "executing: " + d.executing + ", " +
                               "state: " + d.state; });
}

// not used
function nodeMouseOut(d) {
  d3.select(this).selectAll(".nodebox")
   .transition()
   .duration(sduration)
   .style("fill", null)
   .style("opacity", null);

  svg.selectAll(".link")
    .transition()
    .duration(sduration)
    .style("stroke", null)
    //.style("stroke-width", function(d){return 5E-3*d})
    .style("stroke-width", function(d) {
      return defaultStroke;
    });
  // remove details
  thisNode.select('#nodeDetails1')
    .text(function(d) { return ""; });
  thisNode.select('#nodeDetails2')
    .text(function(d) { return ""; });
}

function getPerformance(d) {
  if (d.node_type == "manager") {
    return yscale_performancebar(d.finished / d.total);
  } else if (d.node_type == "controller") {
    return yscale_performancebar(d.executing / d.parent.executing);
  } else {
    return yscale_performancebar(d.executing / d.parallel);
  }
}

function getTypeColor(d) {
  if (d.node_type == "manager") {
    return "green";
  } else if (d.node_type == "controller") {
    return "orange";
  } else {
    return "steelblue";
  }
}

d3.select(self.frameElement).style("height", (height + 100) + "px");
