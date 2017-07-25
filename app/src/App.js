import React, { Component } from 'react';
import AceEditor from 'react-ace';
import Dropdown from 'react-dropdown';
import debounce from 'debounce';
import urlParse from 'url-parse';

import 'brace/mode/json';
import 'brace/mode/csharp';
import 'brace/mode/golang';
import 'brace/mode/swift';
import 'brace/theme/github';
import 'brace/theme/cobalt';

import Main from "../../output/Main";
import Samples from "../../output/Samples";

class Editor extends Component {
  constructor(props) {
    super(props);
    this.state = {
      value: props.value
    };
  }

  componentDidMount() {
    this.getEditor().setOption("displayIndentGuides", false);
  }

  getEditor = () => window.ace.edit(this.getName())
  getName = () => this.props.className + "-editor"

  render() {
    return (
      <div className={this.props.className}>
        <div className="titleBar">{this.props.language}</div>
        <div className="editor-container">
          <AceEditor
            name={this.getName()}
            mode={this.props.language}
            theme={this.props.theme}
            fontSize="10pt"
            showGutter={false}
            onChange={this.props.onChange}
            highlightActiveLine={false}
            showPrintMargin={false}
            displayIndentGuides={false}
            editorProps={{$blockScrolling: true}}
            value={this.props.value}
          />
        </div>
      </div>
    );
  }
}

class TopBar extends Component {
  samples = Samples.samples;

  constructor(props) {
    super(props);

    let { query } = urlParse(window.location.href, true);
    let queryExtension = query.lang || query.l;
    let queryRenderer = queryExtension && Main.renderers.find((r) => r.extension === queryExtension);

    this.state = {
      sample: localStorage["sample"] || this.samples[0],
      renderer: queryRenderer || this.getRenderer()
    };
  }

  componentWillMount() {
    this.changeSample(this.state.sample);
    this.changeRenderer(this.state.renderer.name);
  }

  componentDidMount() {
    // TODO why is widgets sometimes undefined?
    window.twttr.widgets && window.twttr.widgets.load();
  }

  sendEvent = (name, value) => window.ga("send", "event", "TopBar", name, value);

  changeSample = (sample) => {
    this.sendEvent("changeSample", sample);

    try {
      localStorage["sample"] = sample;
    } catch (e) {}

    this.setState({ sample }, () => this.refresh());
  }

  refresh = () => {
    fetch(`/sample/json/${this.state.sample}`)
      .then((data) => data.json())
      .then((data) => {
        let pretty = JSON.stringify(data, null, 2);
        this.props.onChangeSample(pretty);
      });
  }

  getRenderer = (name) => {
    let theName = name || localStorage["renderer"] || Main.renderers[0].name;
    return Main.renderers.find((r) => r.name === theName) || Main.renderers[0];
  }

  changeRenderer = (name) => {
    this.sendEvent("changeRenderer", name);

    let renderer = this.getRenderer(name);
    this.setState({ renderer: renderer.name });
    
    try {
      localStorage["renderer"] = renderer.name;
    } catch (e) {}

    this.props.onChangeRenderer(renderer);
  }

  render() {
    return (
      <div className="topBar">
        <div className="controls">
          <Dropdown
            name="sample"
            options={this.samples}
            value={this.state.sample}
            onChange={({value}) => this.changeSample(value)} />
          <Dropdown
            name="renderer"
            options={Main.renderers.map((r) => r.name)}
            value={this.getRenderer().name}
            onChange={({value}) => this.changeRenderer(value)} />
        </div>
        <a className="what-is-this"
          href="http://blog.quicktype.io/2017/previewing-quicktype"
          target="_new">
          What is this?
        </a>
        <a className="twitter-follow-button"
          data-size="large"
          data-show-count="false"
          href="https://twitter.com/quicktypeio">
          Follow @quicktypeio
        </a>
     </div>
    );
  }
}

class App extends Component {
  constructor(props) {
    super(props);
    this.state = {
      left: "",
      right: "",
      renderer: Main.renderers[0]
    };
  }

  sendEvent = (name, value) => window.ga("send", "event", "App", name, value);

  sendPerformance = (category, variable, work) => {
    let start = window.performance && window.performance.now();
    let result = work();
    let elapsed = start && (window.performance.now() - start);

    if (elapsed) {
      window.ga('send', 'timing', category, variable, Math.round(elapsed));
    }

    return result;
  }

  sourceEdited = (newValue) => {
    let renderer = this.state.renderer;
    let result = this.sendPerformance("Main", "renderJsonString", () => Main.renderJsonString(renderer)(newValue));

    this.sendEvent("sourceEdited");

    if (result.constructor.name === "Left") {
      console.log(result.value0);
      this.setState({
        left: newValue
      });
    } else {
      this.setState({
        left: newValue,
        right: result.value0
      });
    }
  }

  changeRenderer = (renderer) => {
    this.setState({ renderer }, () => {
      this.sourceEdited(this.state.left);
    });
  }

  render() {
    return (
      <div>
        <TopBar
          onChangeSample={this.sourceEdited}
          renderer={this.state.renderer}
          onChangeRenderer={this.changeRenderer} />
        <div id="editors">
          <Editor
            className="left"
            language="json"
            theme="github"
            onChange={debounce(this.sourceEdited, 300)}
            value={this.state.left}
          />
          <Editor
            className="right"
            language={this.state.renderer.aceMode}
            theme="cobalt"
            value={this.state.right}
          />
        </div>
      </div>
    );
  }
}

export default App;
