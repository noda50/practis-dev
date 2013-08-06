var margin = {top: 20, right: 20, bottom: 30, left: 40},
    width = 960 - margin.left - margin.right,
    height = 500 - margin.top - margin.bottom;

var x = d3.scale.linear()
    .range([0, width]);

var y = d3.scale.linear()
    .range([height, 0]);

var color = d3.scale.category10();

var xAxis = d3.svg.axis()
    .scale(x)
    .orient("bottom");

var yAxis = d3.svg.axis()
    .scale(y)
    .orient("left");

var svg = d3.select("body").append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom)
  .append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

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

function hslcolor(h, s, l) {
  return d3.hsl(h, s, l).toString();
}

function pcolormap(v) {
  return hslcolor(v * 180.0 + 180.0, 0.7 * v, 0.5);
}

var cmap = d3.select('#color-map').append("svg")
    .attr("id", "color-map")
    .attr("width", 70)
    .attr("height", 7);
for (var i = 0.0; i < 10.0; i += 1.0) {
    cmap.append("rect")
        .attr("class", "cell")
        .attr("x", i * 7.0)
        .attr("y", 0.0)
        .attr("width", 6)
        .attr("height", 6)
        .style("fill", function(d) {
          return pcolormap(i / 10.0);});
          //return d3.hsl(i * 360.0 / 10.0, 0.8, 0.5).toString();});
}

// url = "data/scatterplot.tsv";
// url = "data/scatterplot.json";
// url = "http://localhost:4567/results.json";
url = "results.json";

var parameters = [],
    results = [],
    result_data = [];

d3.json(url, function(error, json) {

  // console.log(json);

  json.parameters.forEach(function(d) {
    parameters.push(d);
  });
  // console.log(parameters);

  json.results.forEach(function(d) {
    results.push(d);
  });
  // console.log(results);

  json.result_data.forEach(function(d) {
    var parameter = [],
        result = [];
    parameters.forEach(function(p) {
      // parameter.push(d.parameters[p]);
      parameter[p] = d.parameter[p];
    });
    results.forEach(function(r) {
      result[r] = d.result[r];
    });
    result_data.push({id: d.id, parameter: parameter, result: result});
  });
  // console.log(result_data);
  parameters.forEach(function(p) {
    d3.select('#x-parameter').append('option').text(p);
    d3.select('#y-parameter').append('option').text(p);
  });
  if (parameters.length > 1) {
    d3.select('#y-parameter').node().selectedIndex = 1;
  }

  results.forEach(function(r) {
    d3.select('#result').append('option').text(r);
  });

  d3.select('#x-parameter').on('change', function() {
    update();
    // console.log("x changed");
  });

  d3.select('#y-parameter').on('change', function() {
    update();
    // console.log("y changed");
  });

  d3.select('#result').on('change', function() {
    update();
    // console.log("result changed");
  });

  update();

  function update() {
    // get selection
    var x_i = d3.select('#x-parameter').node().selectedIndex;
    var x_v = d3.select('#x-parameter').node().options[x_i].value;
    var y_i = d3.select('#y-parameter').node().selectedIndex;
    var y_v = d3.select('#y-parameter').node().options[y_i].value;
    var r_i = d3.select('#result').node().selectedIndex;
    var r_v = d3.select('#result').node().options[r_i].value;

    // console.log(r_v);
    var max_l = Math.max.apply(null, result_data.map(function(i) { return i.result[r_v]; }));
    var min_l = Math.min.apply(null, result_data.map(function(i) { return i.result[r_v]; }));
    // var min_l = Math.min.apply(null, json.map(function(i) { return i.petalLength; }));
    // console.log(max_l);
    // console.log(min_l);

    x.domain(d3.extent(result_data, function(d) { return d.parameter[x_v]; })).nice();
    y.domain(d3.extent(result_data, function(d) { return d.parameter[y_v]; })).nice();

    // clean
    var oldg = svg.selectAll("g");
    if (oldg.length > 0) {
      if (oldg[0].length > 1) {
        oldg.remove();
      }
    }
    var olddot = svg.selectAll(".dot");
    if (olddot.length > 0) {
      if (olddot[0].length > 1) {
        olddot.remove();
      }
    }
    var oldlegend = svg.selectAll(".legend");
    if (oldlegend.length > 0) {
      if (oldlegend[0].length > 1) {
        oldlegend.remove();
      }
    }

    svg.append("g")
        .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

    svg.append("g")
        .attr("class", "x axis")
        .attr("transform", "translate(0," + height + ")")
        .call(xAxis)
      .append("text")
        .attr("class", "label")
        .attr("x", width)
        .attr("y", -6)
        .style("text-anchor", "end")
        .text("parameter: " + x_v);

    svg.append("g")
        .attr("class", "y axis")
        .call(yAxis)
      .append("text")
        .attr("class", "label")
        .attr("transform", "rotate(-90)")
        .attr("y", 6)
        .attr("dy", ".71em")
        .style("text-anchor", "end")
        .text("parameter: " + y_v)

    svg.selectAll(".dot")
        .data(result_data)
      .enter().append("circle")
        .attr("class", "dot")
        .attr("r", function(d) {
          //return d.result[r_v]; })
          //console.log(d.result[r_v]);
          return get_r(d.result[r_v]); })
        .attr("cx", function(d) { //console.log("x:" + d.parameter[x_v]);
          return x(d.parameter[x_v]); })
        .attr("cy", function(d) { //console.log("y:" + d.parameter[y_v]);
          return y(d.parameter[y_v]); })
        //.style("fill", function(d) { return "black"; })
        .style("opacity", 0.9)
        .style("fill", function(d) { return get_color(d.result[r_v]); })
        .on("mouseover", function(d) {
          divpopup.selectAll("#popup-title").text("Parameter (" + x_v + ":" +
              d.parameter[x_v] + ", " + y_v + ":" + d.parameter[y_v] + ")");
          var result_text = "id: " + d.id + ",\n";
          results.forEach(function(r) {
            result_text += r + ": " + d.result[r] + ",\n";
          });
          divpopup.selectAll("#popup-content").text(result_text);
          divpopup.selectAll("#popup-desc").text(r_v + ": " + d.result[r_v]);
          divpopup
            .style("visibility", "visible");
         })
        .on("mousemove", function(d) {
          divpopup.style("left", (event.clientX + 10) + "px")
              .style("top", (event.clientY - 50) + "px");
          // divpopup.style("top", (event.pageY - 80) + "px")
          //   .style("left", (event.pageX + 10) + "px");
        })
        .on("mouseout", function(d) {
          d3.selectAll("text").classed("active", false);
          divpopup
            .style("visibility", "hidden");
        });

    var legend = svg.selectAll(".legend")
        .data(color.domain())
      .enter().append("g")
        .attr("class", "legend")
        .attr("transform", function(d, i) { return "translate(0," + i * 20 + ")"; });

    legend.append("rect")
        .attr("x", width - 18)
        .attr("width", 18)
        .attr("height", 18)
        .style("fill", color);

    legend.append("text")
        .attr("x", width - 24)
        .attr("y", 9)
        .attr("dy", ".35em")
        .style("text-anchor", "end")
        .text(function(d) { return d; });

    function get_r(d) {
      if (d < min_l || d > max_l) {
        console.log("invalid value");
        return 3.5;
      }
      return 1.0 + 19.0 * (d - min_l) / (max_l - min_l);
    }

    function get_color(d) {
      if (d < min_l || d > max_l) {
        console.log("invalid value");
        return pcolormap(0.0);
      }
      return pcolormap((d - min_l) / (max_l - min_l));
    }
  }
});

d3.select(self.frameElement).style("height", (height + 150) + "px");
