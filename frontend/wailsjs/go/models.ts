export namespace main {
	
	export class Config {
	    model: string;
	    language: string;
	    hotkey: string;
	    window_x?: number;
	    window_y?: number;
	
	    static createFrom(source: any = {}) {
	        return new Config(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.model = source["model"];
	        this.language = source["language"];
	        this.hotkey = source["hotkey"];
	        this.window_x = source["window_x"];
	        this.window_y = source["window_y"];
	    }
	}
	export class ConfigService {
	
	
	    static createFrom(source: any = {}) {
	        return new ConfigService(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	
	    }
	}
	export class ModelService {
	
	
	    static createFrom(source: any = {}) {
	        return new ModelService(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	
	    }
	}

}

