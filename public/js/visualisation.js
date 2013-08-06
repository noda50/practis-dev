
// Initial variables about font sizes, and dimensions of the diagram
var fontSize = 8
var lineSpace = 2
var boxHeight = 50
var boxWidth = 85
var width = 625
var height = 1000
var yscale_performancebar = d3.scale.linear()
                                .domain([0,1])
                                .rangeRound([boxHeight/2,-boxHeight/2])

var cluster = d3.layout.cluster()
    .size([height, width - 160]);


var diagonal = d3.svg.diagonal()
    .projection(function(d) { return [d.y, d.x]; });

var svg = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height)
  .append("g")
    .attr("transform", "translate(80,0)");


// Setting up json data
var jsonFile = "local_local-hlnp.json"

// Load a json file, and perform the following function when it loads
d3.json(jsonFile, function(error, root) {
    var nodes = cluster.nodes(root),
        links = cluster.links(nodes);
    
    //DATA JOIN: Bind existing objects to new data
    var existingLinks = svg.selectAll(".link")
    		      .data(links)
    var existingNodes = svg.selectAll(".node")
    		    .data(nodes)
    	    
    //UPDATE: Update old elements (before making new ones)
    
    //ENTER: Create new objects where necessary
    existingLinks.enter().append("path")
    	.attr("class", "link")
    	.attr("d", diagonal)
    
    newNodes = existingNodes.enter().append("g")
    newNodes
    	.attr("class", "node")
    	.attr("id", function(d){return d.name})
    	.attr("transform", function(d) { return "translate(" + d.y + "," + d.x + ")"; })
    .append("rect")
        .attr('class', 'nodebox')
    		.attr("x", -boxWidth/2)
    		.attr("y", -boxHeight/2)
    		.attr("width", boxWidth)
    		.attr("height", boxHeight)
    newNodes.append("rect")
    .attr('id', 'performancebar')
    .attr("x", boxWidth/2*1.05)
    .attr("width", boxWidth/10)
    .style("fill", "red")
    .style("stroke", "red")
    .attr("y", boxHeight/2)
    .attr("height", 0)
    
    // Highlight node when we mouse-over
    newNodes.on("mouseover", function() {
    thisNode = d3.select(this)
    thisNodeCol = thisNode.select(".nodebox").style("stroke")
    thisNode.selectAll(".nodebox")
    	.transition()
    	.duration(250)
    	    .style("fill", thisNodeCol)
    // 	            .style("opacity", 0.6)
        svg.selectAll(".link")
           .transition().duration(250)
           .style("stroke", thisNodeCol)
       .style("stroke-width",  getLinkWidthClass)
    })
    newNodes.on("mouseout", function(){
    d3.select(this).selectAll(".nodebox")
       .transition()
       .duration(250)
           .style("fill", null)
           .style("opacity", null)
    svg.selectAll(".link")
       .transition().duration(250)
        .style("stroke", null)
        .style("stroke-width", function(d){return 5E-3*d.target.params.nKPsForThisNode})
    })
    		
    //Add node titles
    newNodes.append("text")
    	.attr("id", "nodetitle")
    	.attr("class", "nodeTitle")
    	.attr("y", -boxHeight/2 + fontSize + 2*lineSpace)
    	.attr("text-anchor", "middle")
    
    //Add node body text (for f1 score)
    newNodes.append("text")
    .attr("text-anchor", "middle")
    .attr("class", "nodeText")
    .attr("id", "f1Text")
    .attr("y", -boxHeight/2 + 2*fontSize + 3*lineSpace)
    
    newNodes.append("g")
    .attr("class", "confusionmatrix")
    .attr("id", "confusionmatrix")
        .selectAll("g").data(function(d){return d.params.confusionmatrix})
        .enter().append("g")
    	.attr("class", "rows")
    	.attr("transform", function(d,i) { return "translate("+(-15)+"," + (-boxHeight/2 + (i+3)*fontSize+(i+4)*lineSpace) + ")"; })
    	.selectAll("g").data(function(d){return d})
    	.enter().append("g")
    	    .attr("class", "columns")
    	    .attr("transform", function(d,i) { return "translate(" + i*30 + ",0)"; })
    				.append("text")
    					.attr("text-anchor", "middle")
    					.attr("class", "nodeText")
    
    //ENTER + UPDATE: Update all nodes with new attributes
    existingNodes.select('#performancebar')
    .transition()
    .duration(1000)
    .attr("y", function(d){
    		return yscale_performancebar(d.params["f1-score"])
    		})
    .attr("height", function(d){
    		return boxHeight/2 - yscale_performancebar(d.params["f1-score"])
    		})
    existingLinks
    .transition()
    .duration(1000)
    .style("stroke-width", function(d){return 5E-3*d.target.params.nKPsForThisNode})
    
    existingNodes.select("#nodetitle")
    .text(function(d){return d.name.split("_").slice(-1)})
    existingNodes.select("#f1Text")
    .text(node1Text)
    
    
    // Update confusion matrix
    existingNodes.select("#confusionmatrix")
    .selectAll(".rows")
    .data(function(d){return d.params.confusionmatrix})
        .selectAll(".columns") //rows
        .data(function(d){return d})
    	.select("text")
    	.text(function(d){return d})
})
    
// Format f1score message
function node1Text(d) {
    var f1Score = d.params["f1-score"]
    return "f1-Score: " + d3.format("0.1f")(f1Score*100) + "%"
}

function getLinkWidthTotal(node) {
    return 5E-3*d.target.params.nKPsForThisNode

}

function getLinkWidthClass(node) {
    var className = thisNode.attr("id")
    var rootNode = d3.select('#RootNode')[0][0].__data__
    var rootInst = rootNode.params.numInstToThisNode[className]
    var normFac = rootInst / boxHeight
    var thisNodeInst = node.target.params.numInstToThisNode[className]
    var myWidth = thisNodeInst / normFac
    return myWidth
}

d3.select(self.frameElement).style("height", height + "px");
